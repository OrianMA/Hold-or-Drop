# Architecture — Hold or Drop

> Reference document for the codebase. Read this before making structural changes.
> Keep it in sync when systems, services, events, or data flows change.

## 1. Game Concept

**Hold or Drop** is a Roblox risk/reward game. Each player owns a private room with a
button. Holding the button grows a **multiplier** over time, increasing the payout — but
the **explosion risk** also ramps up. The player chooses when to **release** (bank the
cash) or keep **holding** (greed). If the button explodes, a short **perfect-parry** window
gives one last chance to survive; failing it kills the player and pays only a fraction of
the pot.

Core loop: *enter room → trigger button → hold (multiplier ↑, risk ↑) → release / explode →
parry chance → end-game payout animation → money credited*.

## 2. Tech Stack & Build

| Concern        | Tool |
|----------------|------|
| Language       | TypeScript via **roblox-ts** (`rbxtsc`) |
| Place sync     | **Rojo** (`default.project.json`) |
| Toolchain mgmt | **Rokit** (`rokit.toml`) / Aftman (`aftman.toml`) |
| Lint/format    | ESLint + Prettier + `eslint-plugin-roblox-ts` |
| Roblox types   | `@rbxts/types`, `@rbxts/compiler-types`, `@rbxts/services` |

**Build:** `npm run build` (one-shot) / `npm run watch` (incremental).
TypeScript in `src/` compiles to Luau in `out/`. **Never edit `out/` by hand** — it is
generated. Commit `out/` changes only as a product of a build.

### Rojo place mapping (`default.project.json`)

| Source            | Roblox location |
|-------------------|-----------------|
| `out/server`      | `ServerScriptService/TS` |
| `out/shared`      | `ReplicatedStorage/TS` |
| `out/client`      | `StarterPlayer/StarterPlayerScripts/TS` |
| `node_modules/@rbxts` | `ReplicatedStorage/rbxts_include/node_modules/@rbxts` |

`tsconfig.json` sets `baseUrl: src`, so imports are absolute from `src/`:
`import { Events } from "shared/Event"`, `import { RoomService } from "server/rooms/RoomService"`.

## 3. Directory Layout

```
src/
├── server/                  # ServerScriptService — authoritative game logic
│   ├── main.server.ts       # Entry: iterates services and calls init()
│   ├── services/
│   │   ├── index.ts         # Service registry + boot ORDER (critical)
│   │   ├── RoomService… (rooms/) PlayerDataService, PlayerProgressionService,
│   │   ├── ShopService, ButtonTriggerService, ButtonSessionService, CharacterService, UiService
│   ├── rooms/
│   │   ├── Room.ts          # One room wrapper (parts, ownership, billboard)
│   │   └── RoomService.ts   # player ↔ room assignment
│   ├── modules/
│   │   ├── ButtonModule.ts          # Per-room trigger handler
│   │   ├── ButtonInGameModule.ts    # THE hold/risk/parry game loop
│   │   ├── EndGameButtonModule.ts   # Post-game payout + popup coordination
│   │   ├── ConfettiBurst.ts, CheatConfig.ts
│   ├── UI/
│   │   ├── Popup.ts                 # Base popup (Show/Hide a named Frame)
│   │   ├── PopupConfig.ts           # PopupType → behavior class registry
│   │   ├── PopupBehaviors/          # ButtonMenu / ButtonInGame / ButtonFinishGame
│   │   └── Interface/IPopup.ts
│   └── main.server.ts
├── client/                  # StarterPlayerScripts — visuals, input, camera
│   ├── main.client.ts       # Entry: wires up all client behaviors
│   ├── behaviors/           # ButtonMenu / ButtonInGame / EndGameButton / Shop behaviors
│   │   └── ShopBehavior (open/close) + ShopItemsController (the 4 upgrade buttons)
│   ├── rooms/RoomPromptController.ts  # Per-client ProximityPrompt visibility
│   └── ui/                  # HUD + effects (MoneyDisplay, InGameUIController, etc.)
└── shared/                  # ReplicatedStorage — code/data used by both sides
    ├── Event.ts             # RemoteEvent catalog (Events namespace)
    ├── Utils/DefineEvent.ts # Creates (server) / waits for (client) a RemoteEvent
    ├── ButtonGameConfig.ts  # Shared gameplay tuning constants
    ├── ShopBalance.ts       # Shop economy numbers (THE rebalancing file)
    ├── ShopConfig.ts        # Shop items + price/value formulas (logic, reads ShopBalance)
    ├── PopupType.ts         # Popup enum (shared contract)
    ├── NumberFormat.ts      # FormatCash helper
    └── CameraController.ts  # Scriptable camera helper (client-only at runtime)
```

## 4. Client / Server / Shared Boundaries

- **Server is authoritative.** All gameplay decisions — risk rolls, explosion, payout,
  ownership validation, persistence — happen on the server. The client never decides
  outcomes; it only sends intent (release/parry/quit) and renders effects.
- **Client owns presentation:** camera, post-processing, sounds, HUD, popups, and
  per-player ProximityPrompt visibility.
- **Shared** holds the *contracts* both sides agree on: the RemoteEvent list, popup
  identifiers, and gameplay timing constants — so client effects stay in sync with server
  logic.

## 5. Bootstrapping & Service Order

`main.server.ts` simply iterates `services` (from `services/index.ts`) and calls `init()`
on each. **Order is load-bearing** and documented inline in `index.ts`:

1. `UiService.init(PopupConfig)` — register popup classes
2. `PlayerDataService` — load/persist `Money`
3. `PlayerProgressionService` — load/persist the progression **levels** + `Rebirths`, derive
   `BaseCash`, `Multiplier`, `AdditionalSecurity`, `MultRebirth` (must run before RoomService
   so the `BaseCash` attribute exists at room assignment)
4. `ShopService` — handle cash purchases (needs PlayerData + PlayerProgression ready)
5. `RebirthService` — handle `RebirthEvent`: validate `Money ≥ rebirthCost(Rebirths)`, reset
   `Money` + stat levels, increment `Rebirths` (needs PlayerData + PlayerProgression ready)
6. `RoomService` — scan `Workspace/PlayerZones`, build rooms, assign players
7. `ButtonTriggerService` — attach a `ButtonModule` to each room (needs rooms built first)
8. `CharacterService` — normalize character scale on spawn
9. `EndGameButtonModule.init()` — wire the payout-finished handshake
10. `PlayerRemoving` → `ButtonSessionService.cleanup` — release session on disconnect

The client (`main.client.ts`) initializes its behaviors/controllers eagerly; most only act
once a server event fires.

## 6. Core Systems

### 6.1 Rooms (`rooms/Room.ts`, `rooms/RoomService.ts`)
- A **Room** wraps one `Workspace/PlayerZones/P{n}` folder containing a `ButtonModel`
  (`ButtonPart` + `ProximityPrompt`, `PlayerPosPlaceHolder`, `CameraPosPart`, optional
  `UiPart/BillboardGui/GainText`). Invalid layouts are skipped with a warning.
- **Ownership is the access rule:** only the assigned occupant may trigger the button.
- `RoomService` assigns the first free room on join (numeric-aware `P1<P2<…<P10` sort),
  releases it on leave, and mirrors the occupant's live `BaseCash` onto the billboard.
- **Spawning:** each room folder may hold a spawn marker — a plain `Part` named one of
  `SPAWN_PART_NAMES` (`RespawnLocation`/`SpawnLocation`/`SpawnPart`, resolved in `Room.ts`).
  On assign, `RoomService` connects `player.CharacterAdded` to teleport the occupant onto
  that part on every (re)spawn (and moves an already-present character immediately). A real
  `SpawnLocation` instance is **not** required — matching is by name, placement by teleport.
- `ProximityPrompt.Enabled` is **global** (no per-player toggle), so the server keeps every
  prompt **disabled** and publishes `AssignedRoom` / `InSession` attributes per player.
  `RoomPromptController` (client) enables only the local player's prompt — client-side
  writes don't replicate. Server still validates ownership on `Triggered`.
- **Owner display** (optional `OwnerDisplay` model in the room folder):
  - `NamePart/.../NameText` — server writes `"Base of {PlayerName}"` on assign and clears
    it on release; the SurfaceGui replicates so everyone sees the occupant's name.
  - `OwnerIndicatorPart/BillboardGui` — same client-local-enable pattern as the prompt:
    server keeps it disabled, `OwnerIndicatorController` (client) enables it only on the
    local player's assigned room so the "your base" cue is visible to its owner alone.

### 6.2 Button trigger (`modules/ButtonModule.ts`)
One instance per room. On `Triggered`: validates ownership, guards against double-start
(`InSession` lags one round-trip — re-check the session map), creates the session,
sets `InSession=true`, hides the billboard for the active player, teleports + anchors the
player on the button, fires `ButtonTriggerEvent` to the client, and shows the ButtonMenu
popup.

> NOTE: `ButtonModule.onTriggered` currently shows the ButtonMenu popup directly but does
> **not** itself call `startButtonGame`. The hold loop is started server-side; trace the
> `StartButtonClickedEvent` wiring when modifying this flow.

### 6.3 The game loop (`modules/ButtonInGameModule.ts`) — the heart
`startButtonGame(player, session)` reads `BaseCash` + `Multiplier` + `MultRebirth` once (held
for the session) and runs **two independent loops** via `task.spawn`:

- **Multiplier loop** (`MULTIPLIER_TICK_RATE` = 1s): `currentMultiplier += Multiplier` each
  tick, starting from `STARTING_MULTIPLIER` (1). Flat per-second growth.
- **Risk loop** (`TICK_RATE` = 0.5s): `getRisk(t)` is `MAX_RISK * (t/TOTAL_DURATION)²`
  (EaseInQuad, caps at `MAX_RISK` = 0.8 after `RISK_RAMP_DURATION` = 17s), then scaled by
  the player's **Safety**: `risk = getRisk(t) * (1 - safety)` (safety 0..0.5, read once at
  session start). Each tick rolls `math.random() < risk`; also drives the progress bar.

Endings:
- **Release** (`ReleaseButtonEvent`): pays `floor(baseCash * currentMultiplier * MultRebirth)`, confetti, → EndGame.
- **Explosion roll hits:** fire `ButtonExplodedEvent`, open a **0.2s grace** (player can
  still release to cancel), then a **0.5s perfect-parry window** (`PerfectParryEvent`):
  - **Parry success:** visual-only explosion (`blastPressure=0`), sparkle effect, knockback
    tween, full payout. Movement frozen during the window, restored after.
  - **Parry fail:** lethal explosion (`EXPLOSION_KILL_PRESSURE`), disable Motor6Ds,
    `Humanoid.Health=0`, pay only `floor(baseCash * LOOSE_WIN_MULTIPLIER * currentMultiplier * MultRebirth)`.

> All four payout paths (release, grace-cancel, parry-success, death) are floored and scaled
> by the permanent `MultRebirth` (see §6.6). `MultRebirth` is read once at session start so a
> mid-run rebirth can't change an in-progress hold.

The explosion (`triggerExplosionAt`) uses a tight `BlastRadius` (12) so the fling is scoped
to the anchored player; the sound is cloned from a **pre-buffered ReplicatedStorage
template** to avoid a CDN fetch at runtime.

### 6.4 End game (`modules/EndGameButtonModule.ts`)
`enter(...)` cleans up the session, stashes `pendingEarned`, then (after a delay or
respawn) shows the `ButtonFinishGame` popup and fires `EndGameStartEvent` (baseCash,
multiplier, lossMultiplier, **multRebirth**) to drive the client payout animation — the
client folds `multRebirth` into the displayed total so it matches the credited amount. The client signals
`EndGameFinishedEvent` when the animation ends → server credits `Money` and hides the popup.
**Money is credited only after the client animation completes** (single source of truth).

### 6.5 Popups (`UI/Popup.ts`, `UI/PopupConfig.ts`, `services/UiService.ts`)
- `PopupType` enum (`shared/PopupType.ts`): `ButtonMenu`, `ButtonInGame`, `ButtonFinishGame`.
- Server `PopupConfig` maps each type to a behavior class; `UiService` shows/hides by type
  and tracks one current popup per player (showing a new one hides the previous).
- A popup resolves `PlayerGui/InGameUI/<className>` Frame and toggles `Visible`.
- Client mirrors this with `PopupBehaviors/` + `behaviors/` that animate the frames.

### 6.6 Persistence (`PlayerDataService`, `PlayerProgressionService`)
- Both follow the same pattern: **DataStore-backed, mirrored to player Attributes** so the
  owning client can read state directly via replication.
- `PlayerDataService` → `Money` (store `PlayerData_v1`).
- `PlayerProgressionService` → stores the **levels** `BaseCashLevel`, `MultiplierLevel`,
  `SafetyLevel` **and the `Rebirths` count** (store `PlayerProgression_v2`). The effective
  values `BaseCash`, `Multiplier`, `AdditionalSecurity` are **derived** from the levels, and
  `MultRebirth` is derived from `Rebirths`, all via `shared/ShopConfig` and mirrored to
  attributes (levels, values, `Rebirths` and `MultRebirth` all replicate). Storing levels/count
  means the curves can be retuned later with **zero save migration** — and `Rebirths` is a new
  field that defaults to 0 for existing saves (no version bump).
- `rebirth(player)` (the only rebirth mutation) resets the 3 stat levels to 0 and increments
  `Rebirths`, re-deriving every value. It does **not** touch `Money` — `RebirthService` zeroes
  that via `PlayerDataService` so each service owns its own store.
- **Safe-save guard:** only players whose load succeeded are added to `loadedPlayers` and
  thus eligible to save — a transient load failure never wipes progress.
- `BindToClose` saves all players in parallel within the ~30s shutdown budget.
- `get/set/add(player, key, …)` are the public accessors. Bump `STORE_NAME` (`_v2`) to wipe
  everyone. **API Services must be enabled** in Studio for DataStores to work.

> `AdditionalSecurity` (0..0.5, sold as **Safety** in the shop) scales the explosion risk:
> the risk loop reads it once at session start and applies `risk *= (1 - safety)` (see §6.3).

### 6.7 Camera & HUD (client)
- `CameraController` (shared): `SetCinematic` (Scriptable), `AnimateTo` (tween CFrame),
  `BringBackPlayerCamera` (return to character + reset to Custom).
- `InGameUIController`: toggles the persistent HUD Frame named `HUD` (sibling of the
  popups inside the `InGameUI` ScreenGui) — hidden during active gameplay, re-enabled on quit / result.
- **Persistent GUI:** `InGameUI.ResetOnSpawn = false` is set directly on the ScreenGui in
  Studio so it survives death/respawn. `main.client.ts` additionally sets
  `StarterGui.ResetPlayerGuiOnSpawn = false` as a player-wide safety net. Client behaviors
  cache their UI references once at startup; without this guard, respawning would wipe
  `PlayerGui`, destroy the cached `startButton`/`quitButton`/etc., and silently break
  ButtonMenu et al. (subsequent `Activated.Connect` calls would land on dead instances).
- `ButtonInGameBehavior` owns the heavy game-feel: vignette, ColorCorrection, Bloom, FOV
  zoom, and a two-binding camera-shake design (restore clean CFrame at Camera-1, apply
  shake at Camera+1) to avoid spring drift. It listens to all the server gameplay events
  and translates them into effects.

### 6.8 Shop (`shared/ShopConfig.ts`, `server/services/ShopService.ts`, `client/behaviors/ShopItemsController.ts`)
- The shop sells three upgrades from `Workspace/Shop` (ProximityPrompt → `InGameUI/ShopMenu`,
  open/close handled by `ShopBehavior`). Four buttons map to the upgrades:
  `AButtonMoney` = BaseCash +1, `BX5ButtonMoney` = BaseCash +5, `CMultiplier` = Multiplier +1,
  `DSafety` = Safety +1.
- **`ShopBalance` (shared)** holds every tunable economy number (start prices, value/price
  growth, Safety cap) and nothing else — **the file to edit when rebalancing**.
- **`ShopConfig` (shared)** is the structure + logic, fed by `ShopBalance`: `ITEMS`, per-stat
  `STATS` (value attribute, level attribute, `startPrice`, optional `maxLevel`, `valueFor`,
  `display`) and pure pricing helpers — `priceForLevel` = `floor(start * PRICE_GROWTH^level)`,
  `priceForItem` (strict sum of the next N levels), `isAtCap`. Imported by both sides so
  prices/stat previews computed on the client always match the server.
  - Curves: BaseCash `floor(100 * 1.2^level)`, Multiplier `0.1 * 1.18^level` (uncapped),
    Safety `level * 0.05` capped at `0.5` (`maxLevel` 10). Start prices 25 / 100 / 500. Value
    growth stays **below** the ×1.5 `PRICE_GROWTH` so ROI decelerates (no runaway).
- **`ShopService` (server)** owns the only mutation path. On `ShopPurchaseEvent` it validates
  the item id, checks the cap, re-checks `Money >= price`, then `PlayerDataService.add(-price)`
  + `PlayerProgressionService.addLevel`. Rejections flash `InformationTextEvent`. The client
  pre-check is UX-only; the server never trusts it.
- **`ShopItemsController` (client)** binds the four frames, renders current→next stat
  (`BoostLyout/CurrentStatText` → `NextStatText`) and the cash price (`BuyButton/TextLabel`),
  greys unaffordable buttons, shows `MAX` at the Safety cap, and fires `ShopPurchaseEvent`.
  It refreshes purely from replicated attributes (`Money` + the three level attributes) — no
  server→client response event. **Robux buttons (`RobuxButton`) are not wired yet.**
### 6.9 Rebirth (`server/services/RebirthService.ts`, `client/behaviors/RebirthMenuBehavior.ts`, `client/behaviors/RebirthMenuController.ts`)
A permanent money multiplier earned by resetting everything. It lives in its **own panel**
(`InGameUI/RebirthMenu`), **independent of the shop** — opened from the HUD button
`InGameUI/HUD/ButtonsFrame/RebirthFrame/ImageButton`, closed via `RebirthMenu/CloseFrame/CloseButton`.
- `ShopConfig` exposes the pure pricing/reward: `rebirthCost(R) = floor(2500 × 2.4^R)` and
  `rebirthMult(R)` (table `[1,2,3,3.5,4,4.5,4.75,5]`, then `+0.25`/rebirth).
- **`RebirthMenuBehavior` (client)** — open/close only; starts hidden regardless of the Studio
  default (mirrors `ShopBehavior`).
- **`RebirthMenuController` (client)** — read-only display driven by the replicated `Money` +
  `Rebirths` attributes (refreshes on either change). Renders the current/next titles
  (`RebirthInfoElements/{CurrentRebirth,NextRebirth}/RebirthLevelTitle` → `"Rebirth {R}"`), the
  `×N` rewards as `"x{mult} money"` (`…/Frame/MultiplierText`), and the progression bar
  (`ProgressionBar/CurrentProgressionFrame` X-scale = `clamp(Money/cost, 0, 1)`,
  `ProgressionBar/BackgroundFrame/MoneyNeededText` = `"{Money}/{cost}"` via `FormatNumber`).
  The buy button (`ButtonsFrame/RebirthButton/Button`) fires `RebirthEvent` when affordable,
  else flashes the information panel client-side via `InformationText.show(...)`.
  `SafeRebirthButton` (a Robux "keep your levels" variant) is present in Studio but **not wired
  yet** (no Developer Product).
- **`RebirthService` (server)** re-validates (`Money ≥ rebirthCost`) and performs the reset —
  never trusts the client. Payout scales by the resulting `MultRebirth` (see §6.3, §6.6).

## 7. Networking — Event Catalog (`shared/Event.ts`)

`DefineEvent` creates the `RemoteEvent` on the server and `WaitForChild`s it on the client,
parented to the `Event` ModuleScript. Direction noted per event:

| Event | Dir | Purpose |
|-------|-----|---------|
| `ButtonTriggerEvent` | S→C | Start menu flow; passes `cameraPosPart` |
| `StartButtonClickedEvent` | C→S | Player clicked Start |
| `ReleaseButtonEvent` | C→S | Player released the button |
| `QuitButtonClickedEvent` | C→S | Player quit the menu |
| `PerfectParryEvent` | C→S | Player parried within the window |
| `PerfectParryEffectEvent` | S→C | Trigger sparkle/knockback visuals |
| `BaseCashEvent` | S→C | Initial base cash for the HUD |
| `ButtonExplodedEvent` | S→C | Explosion roll hit — start grace/parry on client |
| `PlayerKilledEvent` | S→C | Player died from explosion |
| `MultiplierUpdateEvent` | S→C | New current multiplier (drives floating label) |
| `RiskUpdateEvent` | S→C | Current risk value |
| `ProgressUpdateEvent` | S→C | Progress-bar fill [0,1] |
| `GameResultEvent` | S→C | (exploded, earned, multiplier) — re-enable HUD |
| `EndGameStartEvent` | S→C | Start payout animation (baseCash, mult, lossMult, multRebirth) |
| `EndGameFinishedEvent` | C→S | Animation done → server credits money, hides popup |
| `InformationTextEvent` | S→C | Flash info text in HUD (e.g. "Not enough money") |
| `ShopPurchaseEvent` | C→S | Player clicked a cash buy button (arg: `ShopItemId`) |
| `RebirthEvent` | C→S | Player clicked Rebirth (no args) — server validates + resets |

Keep RemoteEvents minimal (per CLAUDE.md). Prefer **player Attributes** for state the
owning client just needs to read (used for `Money`, progression, `AssignedRoom`,
`InSession`).

## 8. Gameplay Tuning Constants

| Constant | Location | Value | Meaning |
|----------|----------|-------|---------|
| `RISK_RAMP_DURATION` | `shared/ButtonGameConfig.ts` | 17s | Risk/progress full ramp |
| `MULTIPLIER_TICK_RATE` | `shared/ButtonGameConfig.ts` | 1s | Multiplier tick interval |
| `STARTING_MULTIPLIER` | `shared/ButtonGameConfig.ts` | 1 | Base payout multiplier |
| `MAX_RISK` | `ButtonInGameModule.ts` | 0.8 | Risk ceiling |
| `TICK_RATE` | `ButtonInGameModule.ts` | 0.5s | Risk-loop interval |
| `LOOSE_WIN_MULTIPLIER` | `ButtonInGameModule.ts` | 0.3 | Payout factor on death |
| `EXPLOSION_BLAST_RADIUS` | `ButtonInGameModule.ts` | 12 | Scoped blast/fling |
| Default `BaseCash` / `Multiplier` | `PlayerProgressionService.ts` | 100 / 0.1 | New-player progression (level 0) |
| Value growth (BaseCash / Multiplier) | `shared/ShopBalance.ts` | ×1.2 / ×1.18 per level | Per-level stat multiplier (must stay < price growth) |
| Price growth | `shared/ShopBalance.ts` | ×1.5 / level | Per-level price multiplier |
| Shop start prices | `shared/ShopBalance.ts` | 25 / 100 / 500 | BaseCash / Multiplier / Safety lvl 1 |
| `Safety` cap | `shared/ShopBalance.ts` | 10 lvls → 50% | Max risk reduction (×5% per level) |
| Rebirth base cost | `shared/ShopBalance.ts` | 2500 | Cash for the 1st rebirth |
| Rebirth cost growth | `shared/ShopBalance.ts` | ×2.4 / rebirth | `cost(R)=floor(2500×2.4^R)` |
| Rebirth mult curve | `shared/ShopBalance.ts` | `[1,2,3,3.5,4,4.5,4.75,5]` +0.25/rebirth | Permanent payout `×MultRebirth` |

## 9. Cheats (`modules/CheatConfig.ts`)

Dev-only flags — **must be `false`/disabled before publishing**:
- `invincible` — button never explodes.
- `resetData` — wipe persisted data on join (fresh default profile each time). **Currently
  `true`** — disable before shipping.

## 10. Conventions (see also `CLAUDE.md`)

- Strong typing; avoid `any`. Prefer simple, readable, single-responsibility files.
- Don't rewrite working systems; modify only what the task needs (CLAUDE.md refactoring rules).
- Server authoritative; keep client/server responsibilities separate.
- Absolute imports from `src/` (`server/…`, `client/…`, `shared/…`).
- Comments may be EN or FR (codebase is mixed); match the surrounding file.
- Mobile players supported by default; consider performance.
```

