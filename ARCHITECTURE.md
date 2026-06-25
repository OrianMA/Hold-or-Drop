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
│   │   ├── NeonPipeColors.ts        # Tints Environment/NeonPipe per room occupancy
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
│   ├── audio/MusicController.ts  # BGM playlist + button-hold music
│   └── ui/                  # HUD + effects (MoneyDisplay, InGameUIController, etc.)
└── shared/                  # ReplicatedStorage — code/data used by both sides
    ├── Event.ts             # RemoteEvent catalog (Events namespace)
    ├── Utils/DefineEvent.ts # Creates (server) / waits for (client) a RemoteEvent
    ├── ButtonGameConfig.ts  # Shared gameplay tuning constants
    ├── AudioConfig.ts       # All sound asset IDs/volumes (music + SFX)
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
4. `BoostService` — resolve group + game-pass ownership into input attributes (`InCommunity`,
   `MoneyTierMult`, `HasSafetyPass`), then call `PlayerProgressionService.recompute` to
   fold them into `MoneyMult` / `EffectiveBaseCash` / `AdditionalSecurity`; needs
   Progression's `recompute`, runs before `RoomService`
5. `ShopService` — handle cash purchases (needs PlayerData + PlayerProgression ready)
6. `RebirthService` — handle `RebirthEvent`: validate `Money ≥ rebirthCost(Rebirths)`, reset
   `Money` + stat levels, increment `Rebirths` (needs PlayerData + PlayerProgression ready)
7. `LeaderboardService` — global money + playtime rankings (OrderedDataStore) and the podium;
   self-driven 60s refresh loop (needs PlayerData ready — reads `Money`/`Playtime`)
8. `RoomService` — scan `Workspace/PlayerZones`, build rooms, assign players
9. `ButtonTriggerService` — attach a `ButtonModule` to each room (needs rooms built first)
10. `CharacterService` — normalize character scale on spawn
11. `EndGameButtonModule.init()` — wire the payout-finished handshake
12. `PlayerRemoving` → `ButtonSessionService.cleanup` — release session on disconnect

The client (`main.client.ts`) initializes its behaviors/controllers eagerly; most only act
once a server event fires.

## 6. Core Systems

### 6.1 Rooms (`rooms/Room.ts`, `rooms/RoomService.ts`)
- A **Room** wraps one `Workspace/PlayerZones/P{n}` folder containing a `ButtonModel`
  (`ButtonPart` + `ProximityPrompt`, `PlayerPosPlaceHolder`, `CameraPosPart`, optional
  `UiPart/BillboardGui/GainText`, optional `CommunityJoinPart`). Invalid layouts are skipped
  with a warning.
- **Ownership is the access rule:** only the assigned occupant may trigger the button.
- `RoomService` assigns the first free room on join (numeric-aware `P1<P2<…<P10` sort),
  releases it on leave, and mirrors the occupant's live **`EffectiveBaseCash`** (not raw
  `BaseCash`) onto the billboard.
- **Community join prompt:** an optional `CommunityJoinPart` sibling of `ButtonModel` carries
  a `ProximityPrompt` **and a `BillboardGui`** ("Rejoindre la communauté (×2 argent)"), both
  globally `Enabled` in Studio so every player sees them. `RoomService` wires the prompt's
  `Triggered` signal to `BoostService.refreshCommunity(player)`, which re-checks group
  `963505568` membership server-side and updates `InCommunity`, then calls
  `PlayerProgressionService.recompute` (the ×2 is folded into `MoneyMult` — see §6.6).
  **`CommunityJoinController` (client, `rooms/CommunityJoinController.ts`)** mirrors the
  replicated `InCommunity` attribute and hides BOTH the prompt and the billboard for members
  (client-local `Enabled` writes, same per-player trick as `RoomPromptController`) — handled
  on spawn for already-members and on the post-trigger re-check for fresh joiners.
  > Roblox provides **no native "join group/community" panel API** (`SocialService`/`GuiService`
  > expose no `PromptGroupJoin`), so the prompt cannot pop a join dialog; it serves as a
  > "claim your ×2 after joining" re-check.
- **Spawning:** each room folder may hold a spawn marker — a plain `Part` named one of
  `SPAWN_PART_NAMES` (`RespawnLocation`/`SpawnLocation`/`SpawnPart`, resolved in `Room.ts`).
  On assign, `RoomService` connects `player.CharacterAdded` to teleport the occupant onto
  that part on every (re)spawn (and moves an already-present character immediately). A real
  `SpawnLocation` instance is **not** required — matching is by name, placement by teleport.
- `ProximityPrompt.Enabled` is **global** (no per-player toggle), so the server keeps every
  prompt **disabled** and publishes `AssignedRoom` / `InSession` attributes per player.
  `RoomPromptController` (client) enables only the local player's prompt — client-side
  writes don't replicate. Server still validates ownership on `Triggered`.
- **Slot colours** (`modules/RoomColors.ts`): the single source of truth for the per-slot
  palette (P1 blue, P2 red, P3 yellow, P4 green, P5 purple; empty = grey), shared by the
  neon pipes and the spotlights below so the two never drift — **edit here to retune**.
- **Neon pipe colour** (`modules/NeonPipeColors.ts`): each room slot has a matching
  `Workspace/Environment/NeonPipe/P{n}` folder of Neon parts. `RoomService` greys every
  pipe at init (empty baseline), tints a slot's pipe its colour on `assign`, and greys it
  again on `release`.
- **Room spotlight** (`modules/RoomSpotlights.ts`): each room holds a
  `Workspace/PlayerZones/P{n}/SpotLight` lamp — a Neon `LightSource` lens wrapping a
  `SurfaceLight` cone. Mirroring the neon pipe, `RoomService` turns every lamp **off** at
  init, lights it in the slot colour (lens + `SurfaceLight`, `Enabled=true`) on `assign`,
  and switches it off (grey lens, `SurfaceLight` disabled — no projected light) on
  `release`. The housing parts are left untouched.
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
`startButtonGame(player, session)` reads `EffectiveBaseCash` + `Multiplier` once (held for
the session) and runs **two independent loops** via `task.spawn`:

- **Multiplier loop** (`MULTIPLIER_TICK_RATE` = 1s): `currentMultiplier += Multiplier` each
  tick, starting from `STARTING_MULTIPLIER` (1). Flat per-second growth.
- **Risk loop** (`TICK_RATE` = 0.5s): `getRisk(t)` is `MAX_RISK * (t/TOTAL_DURATION)²`
  (EaseInQuad, caps at `MAX_RISK` = 0.8 after `RISK_RAMP_DURATION` = 17s), then scaled by
  the player's **Safety**: `risk = getRisk(t) * (1 - safety)` (safety 0..0.70, read once at
  session start — see §6.6). Each tick rolls `math.random() < risk`; also drives the progress bar.

Endings:
- **Release** (`ReleaseButtonEvent`): pays `floor(EffectiveBaseCash * currentMultiplier)`, confetti, → EndGame.
- **Explosion roll hits:** fire `ButtonExplodedEvent`, open a **0.2s grace** (player can
  still release to cancel), then a **0.5s perfect-parry window** (`PerfectParryEvent`):
  - **Parry success:** visual-only explosion (`blastPressure=0`), sparkle effect, knockback
    tween, full payout. Movement frozen during the window, restored after.
  - **Parry fail:** lethal explosion (`EXPLOSION_KILL_PRESSURE`), disable Motor6Ds,
    `Humanoid.Health=0`, pay only `floor(EffectiveBaseCash * LOOSE_WIN_MULTIPLIER * currentMultiplier)`.

> All four payout paths (release, grace-cancel, parry-success, death) are floored and use
> `EffectiveBaseCash` — the rebirth multiplier and all boosts are already folded into it (see
> §6.6). `EffectiveBaseCash` is read once at session start so a mid-run boost change can't
> affect an in-progress hold. There is no separate `MultRebirth` factor at payout time.

The explosion (`triggerExplosionAt`) uses a tight `BlastRadius` (12) so the fling is scoped
to the anchored player; the sound is cloned from a **pre-buffered ReplicatedStorage
template** to avoid a CDN fetch at runtime.

### 6.4 End game (`modules/EndGameButtonModule.ts`)
`enter(...)` cleans up the session, stashes `pendingEarned`, then (after a delay or
respawn) shows the `ButtonFinishGame` popup and fires `EndGameStartEvent`
`(baseCash=EffectiveBaseCash, multiplier, lossMultiplier)` to drive the client payout
animation — the payload already carries the final credited amount so the animation matches
exactly. `multRebirth` was removed from the payload; the client animation no longer has a
gold rebirth phase. The client signals `EndGameFinishedEvent` when the animation ends →
server credits `Money` and hides the popup.
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
- `PlayerDataService` → `Money` **and `Playtime`** (total seconds played, accumulated across
  sessions; defaults 0 for existing saves — no version bump) (store `PlayerData_v1`).
- `PlayerProgressionService` → stores the **levels** `BaseCashLevel`, `MultiplierLevel`,
  `SafetyLevel` **and the `Rebirths` count** (store `PlayerProgression_v2`). The effective
  values `BaseCash`, `Multiplier`, `AdditionalSecurity` are **derived** from the levels, and
  `MultRebirth` is derived from `Rebirths`, all via `shared/ShopConfig` and mirrored to
  attributes (levels, values, `Rebirths` and `MultRebirth` all replicate). Storing levels/count
  means the curves can be retuned later with **zero save migration** — and `Rebirths` is a new
  field that defaults to 0 for existing saves (no version bump).
  - **Derived boost attributes** (`deriveValues` / `recompute`): `MoneyMult` and
    `EffectiveBaseCash` are also derived and mirrored to attributes on every recompute.
    `MoneyMult` uses the **additive bonus model**: `MoneyMult = 1 + Σ(mᵢ − 1)`, i.e.
    `MultRebirth + (InCommunity ? COMMUNITY.mult−1 : 0) + (MoneyTierMult−1)`. All factors
    start at 1 and contribute their excess above 1, so a solo factor of ×2 gives ×2 total.
    `EffectiveBaseCash = floor(BaseCash × MoneyMult)` — this is the value used by the
    billboard, HUD, and payout (§6.3).
    `AdditionalSecurity` now includes the safety pass:
    `AdditionalSecurity = min(shopSafety + (HasSafetyPass ? 0.20 : 0), 0.70)` (cap raised
    from 0.50 to 0.70).
- **`BoostService`** resolves the three live input attributes each session (not persisted,
  no DataStore key, no migration needed):
  - `InCommunity` — `true` if the player is a member of group `963505568`; re-checked
    server-side via `BoostService.refreshCommunity` when the player uses `CommunityJoinPart`.
  - `MoneyTierMult` — the multiplier of the highest money-tier game-pass the player owns
    (table `MONEY_TIERS` in `shared/ShopBalance.ts`; id 0 = inert); defaults to 1.
  - `HasSafetyPass` — `true` if the player owns the safety game-pass (id 0 = inert).
  After writing these attributes `BoostService` calls `PlayerProgressionService.recompute`
  so `MoneyMult` / `EffectiveBaseCash` / `AdditionalSecurity` update immediately.
- `rebirth(player)` (the only rebirth mutation) resets the 3 stat levels to 0 and increments
  `Rebirths`, re-deriving every value. It does **not** touch `Money` — `RebirthService` zeroes
  that via `PlayerDataService` so each service owns its own store.
- **Safe-save guard:** only players whose load succeeded are added to `loadedPlayers` and
  thus eligible to save — a transient load failure never wipes progress.
- `BindToClose` saves all players in parallel within the ~30s shutdown budget.
- `get/set/add(player, key, …)` are the public accessors. Bump `STORE_NAME` (`_v2`) to wipe
  everyone. **API Services must be enabled** in Studio for DataStores to work.

> `AdditionalSecurity` (0..0.70, sold as **Safety** in the shop + optionally boosted by the
> safety game-pass) scales the explosion risk: the risk loop reads it once at session start and
> applies `risk *= (1 - safety)` (see §6.3). The cap is 0.70 = shop 0.50 + pass 0.20.

### 6.7 Camera & HUD (client)
- `CameraController` (shared): `SetCinematic` (Scriptable), `AnimateTo` (tween CFrame),
  `BringBackPlayerCamera` (return to character + reset to Custom).
- `InGameUIController`: toggles the persistent HUD Frame named `HUD` (sibling of the
  popups inside the `InGameUI` ScreenGui) — hidden during active gameplay, re-enabled on quit / result.
- `CostTextRotator` (`ui/CostTextRotator.ts`): cosmetic — a single looping
  `TweenService` tween wobbles `HUD/BottomList/MultiplierBuyButton/CostMovingtext`
  between +10° and −10° (Sine in/out, reversing, `RepeatCount -1`) to draw the eye.
- `HudProgressionController` (`behaviors/HudProgressionController.ts`): drives the HUD
  rebirth-progress bar `HUD/BottomList/ProgressionBar` (`CurrentProgressionFrame` fill +
  `BackgroundFrame/MoneyNeededText`). Shows the same data as the Rebirth menu bar (§6.9),
  `Money / rebirthCost(Rebirths)`, but the fill and number **count up smoothly** via a
  tweened `NumberValue` proxy (same pattern as `MoneyDisplay`): one proxy drives both so
  they stay in sync. First load snaps; a rebirth (cost jump + money reset) snaps; mid-flight
  earnings cancel and restart from the current visual value.
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
  pre-check is UX-only; the server never trusts it. On success it also fires the neon-pipe
  purchase pulse for the buyer's room (`NeonPipeColors.pulse`, see §6.12).
- **`ShopItemsController` (client)** binds the four frames, renders current→next stat
  (`BoostLyout/CurrentStatText` → `NextStatText`) and the cash price (`BuyButton/TextLabel`),
  greys unaffordable buttons, shows `MAX` at the Safety cap, and fires `ShopPurchaseEvent`.
  It refreshes purely from replicated attributes (`Money` + the three level attributes) — no
  server→client response event.
- **Multiplier readout** (`ShopMenu/Header/MultiplierText`): displays the current `MoneyMult`
  and its breakdown (rebirth factor, community bonus, money-tier bonus) so the player can see
  each factor at a glance.
- **`BoostShopController` (client)**: drives the two wired `RobuxButton` purchase prompts:
  - `AButtonMoney` → money-tier upsell (highest unowned `MONEY_TIERS` tier; id 0 = inert,
    button hidden).
  - `DSafety` → safety game-pass upsell (id 0 = inert, button hidden).
  Both buttons are wired via `MarketplaceService:PromptGamePassPurchase`; ownership is
  re-resolved by `BoostService` on `PromptGamePassPurchaseFinished`.
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
  never trusts the client. After rebirth `MultRebirth` grows, which feeds into `MoneyMult` and
  therefore `EffectiveBaseCash` (re-derived by `PlayerProgressionService.recompute` — see §6.6).

### 6.10 Audio (`shared/AudioConfig.ts`, `client/audio/MusicController.ts`)
- **`AudioConfig` (shared)** is the single registry of every sound asset (id + volume):
  the BGM `playlist`, the `buttonGame` hold music, and the `sfx` (server `explosion`,
  client `buttonExplode` / `parry` / `buttonUpgrade`). SFX still play from their existing call
  sites (`ButtonInGameBehavior` client-side, `ButtonInGameModule` server-side, `NeonPipePulse`
  for `buttonUpgrade` — see §6.12) — only the asset definitions are centralised here, so
  re-pointing a sound is a one-line edit.
- **Music is client presentation** (see §4). `MusicController` (client) owns two things,
  parented to `SoundService`:
  - **BGM**: a looping playlist played through the **new audio API** so a spectrum can be read
    for the visualiser (§6.11): an `AudioPlayer` → `AudioFader` → `AudioDeviceOutput` (audible)
    plus a `Wire` branch from the **player** (before the fader) to an `AudioAnalyzer`
    (`SpectrumEnabled`, `WindowSize` Medium). A single track loops via `Looping`; multiple tracks
    advance on `Ended` and wrap back to the first. Started in `main.client.ts`. It **ducks** for
    the whole run: `playButtonMusic` tweens the **`AudioFader.Volume`** (multiplier 1=full / 0=mute)
    to 0 fast (0.4s) — the player's own `Volume` stays constant, so the analyzer (tapped before the
    fader) keeps reading the full spectrum and the **visualiser keeps running through the run**. The
    audible BGM stays silent through the explosion/parry/payout, then `resumeBgm` eases it back in
    slowly (3s) once the run is fully over — on **respawn** (death path, via
    `CharacterAdded`) or at the **end of the payout animation** (survive path, fired from
    `EndGameButtonBehavior`). `resumeBgm` is a no-op unless ducked; a single stored tween is
    cancelled before each new fade. `getBgmAnalyzer()` exposes the analyzer to the visualiser
    (client-only — `GetSpectrum` returns empty server-side).
  - **Button-hold music**: a **classic `Sound`** (unchanged by the audio-API migration), created
    + preloaded at init (no CDN stall on first hold), looped. `ButtonInGameBehavior` drives it —
    `playButtonMusic()` at hold start (`setup`), `stopButtonMusic()` on release (`endInput`) and
    at the instant of explosion (`ButtonExplodedEvent`, before the parry window).
    `stopButtonMusic()` only stops the music (it no longer touches the BGM); both it and
    `resumeBgm` are idempotent.

### 6.11 Audio Visualizer (`client/ui/AudioVisualizer.ts`)
Lobby decoration, 100 % client / presentation — no server logic. Any part tagged
`AudioVisualizer` (CollectionService) gets a `SurfaceGui` + 32 bars (cyan→violet gradient) built
**once**; discovery is by tag (`GetTagged` + `GetInstanceAddedSignal`/`Removed`), so a part can be
moved, resized (Scale layout) or **duplicated anywhere** and it just works. A `RenderStepped` loop
throttled to ~30 Hz reads `MusicController.getBgmAnalyzer():GetSpectrum()` **once** (shared across
all panels), buckets the linear 0–24 kHz bins into 32 **log-spaced** bands (`readBands`), applies a
perceptual **square-root compression** (`SPECTRUM_SCALE`, `COMPRESS_EXP`, `FREQ_MAX` 6 kHz) and a
fast-attack/slow-release smoothing, then writes each bar's `Size` (Scale Y). A part whose **name
contains `Reversed`** renders mirrored in X (bass on the right, treble on the left, colours
included) — for two panels face to face. `GetSpectrum` is client-only; the same `readBands`
boundary can fall back to `Sound.PlaybackLoudness` if needed.

### 6.12 Neon pipe purchase pulse (`server/modules/NeonPipeColors.ts`, `client/ui/NeonPipePulse.ts`)
Visual feedback on a shop purchase: a short segment of colour travels along **both** of the
player's neon tubes from the shop to their button — as if the upgrade physically runs to the
button. 100 % client / presentation (like §6.11).
- **Signal (no RemoteEvent):** `ShopService` calls `NeonPipeColors.pulse(roomName)` after a
  successful purchase (room from the buyer's `AssignedRoom` attribute). `pulse` only
  **increments a `Pulse` attribute** on `Workspace/Environment/NeonPipe/P{n}` — the server
  paints/replicates no colour for the effect.
- **`NeonPipePulse` (client)** watches each `P{n}` folder's `Pulse` attribute. On the first
  pulse for a slot it builds (once, cached) a **shop→button ordering** of each tube's
  (`Right`/`Left`) ~108 parts via a nearest-neighbour walk seeded from the part closest to
  `Workspace/Shop` — the parts are all named `Part`, so order is geometric, not by name.
- **Multiple concurrent segments + queue:** the `Pulse` counter's **delta** drives N segments
  (so several purchases coalesced into one replicated change still each animate). Every purchase
  spawns its own segment that coexists with any already in flight; simultaneous ones are released
  **staggered by `QUEUE_DELAY`** so they read as a clean train rather than one stack. A single
  `RenderStepped` loop advances all live segments of a room, painting each band a **light /
  near-white** shade of the slot colour (`LIGHT_FACTOR` lerp toward white, trailing fade) and
  restoring the base behind them. Both tubes share one segment list so `Right`/`Left` stay in
  sync. The base is sampled live from the pipe (the slot colour the server already painted in
  §6.1), so no colour table is duplicated client-side.
- **Button-arrival effect:** when a segment reaches the button (`progress >= 1`, the instant it
  leaves the live list), `NeonPipePulse` fires a one-shot on that room's button —
  `PlayerZones/P{n}/ButtonModel`: it enables the `ParticleEmmiter.UpgradeButtonParticles`
  emitter for `PARTICLE_DURATION` (1.2 s) then disables it, and plays a 3D electric SFX
  (`AudioConfig.sfx.buttonUpgrade`, a `Sound` created client-side once and parented to
  `ButtonPart`). Both are resolved once in `buildRoomState` and cached on the `RoomState`;
  either may be absent (e.g. a room whose button package lacks the emitter) and is then skipped.
  Overlapping arrivals are handled by a `particleToken` so only the latest 1.2 s timer disables
  the emitter. The emitter sits **disabled** at rest in Studio; its holder part is anchored /
  non-collidable. 100 % client (every client animates the replicated `Pulse`, so all see it).
- **Tunables** (top of `NeonPipePulse.ts`): `SEGMENT_LENGTH` 5, `TRAVEL_TIME` 5 s,
  `LIGHT_FACTOR` 0.85 (0 = slot colour, 1 = white), `QUEUE_DELAY` 0.35 s, `TRAIL_FADE`,
  `PARTICLE_DURATION` 1.2 s.

### 6.13 Button character animations (`client/behaviors/ButtonAnimations.ts`)
Plays the player's rig animations across the button-game flow. 100 % client, layered over the
default Animate idle at `Action` priority. Five assets in `ANIM_IDS`, each of which **must be
owned by / shared with the experience's group (`963505568`)** or Roblox refuses to load it —
the track then plays with `Length 0` (nothing visible), logging *"the experience doesn't have
access permission to use asset id …"*. An empty id is a deliberate no-op so the others keep
working while ids are still being authored.
- `interact` (`123442755794873`, "hand on button") — reaches onto the button then **holds its
  last frame** while the ButtonMenu is open.
- `quit` (`93300469810162`) — one-shot played when the player leaves the menu **before
  pressing**; chains out of the frozen `interact` pose and blends back to defaults at its end.
- `hold` (`100517121510078`, "press button") — presses down then **holds its last frame** for
  the whole game (re-played fresh after a respawn).
- `release` (`70993299432318`) — one-shot when the player releases; defaults at its natural end.
- `parry` (`84361846884673`) — one-shot perfect-parry projection.

**Held poses vs one-shots.** `playInteract`/`playHold` play their clip once then **freeze it on
the last frame** (a `Heartbeat` watcher pins `AdjustSpeed(0)` just before the natural end so the
non-looped track can't auto-stop). Only one held pose at a time (`currentHold`). `playQuit`/
`playRelease`/`playParry` are fire-and-forget one-shots **not** tracked, so they blend back to
Roblox's defaults on their own and a later `stop()` never cuts them short. `stop()` drops only
the held pose; `restoreDefault()` stops everything (held + in-flight one-shot) to force defaults.
Tracks are lazily loaded against the current `Animator` and the cache is dropped on respawn.
Call sites: `ButtonMenuBehavior` (`playInteract` on `ButtonTriggerEvent`, `playQuit` on Quit);
`ButtonInGameBehavior` (`playHold` in `setup`, `playRelease` in `fireRelease`, `playParry` on
`PerfectParryEffectEvent`, `stop` on `GameResultEvent` as a death-path safety net);
`EndGameButtonBehavior` (`restoreDefault` on `EndGameStartEvent` — the payout popup opening ends
the parry projection / any still-playing release clip).

### 6.14 Leaderboards & Podium (`server/services/LeaderboardService.ts`, `server/modules/LeaderboardBoard.ts`, `server/modules/PodiumDisplay.ts`, `shared/LeaderboardConfig.ts`)
Two **global persistent** physical leaderboards + a top-3 money podium, under
`Workspace/Environment/LeaderBoards`. 100 % server-driven — everything replicates, **no
RemoteEvent, no client script**.
- **Data:** two `OrderedDataStore`s — `LB_Money_v1` (value = current `Money`) and
  `LB_Playtime_v1` (value = total seconds). They are a **ranking index only**; the source of
  truth for playtime is the `Playtime` key on `PlayerDataService` (safe-save guarded). Money
  ranks **current** cash, so it drops to 0 on rebirth (see §6.6, §6.9).
- **Loop** (`REFRESH_INTERVAL` 60s, `LeaderboardService`): flush each in-server player's score
  (accumulate playtime delta via `os.time()`, write both stores in `pcall`, spaced by
  `WRITE_SPACING`) → read `GetSortedAsync(false, TOP_N=50)` → resolve names
  (`GetNameFromUserIdAsync`, cached) → render. Also flushes on `PlayerRemoving`. Entire pass in
  `pcall`: a DataStore failure leaves a **stale** display, never a crash. (A brand-new entry can
  miss the first read right after its first write — OrderedDataStore's sorted index updates
  async — and simply appears on the next refresh.)
- **Boards** (`LeaderboardBoard`): each board Part has a `Display` SurfaceGui → `Rows`
  ScrollingFrame + a hidden `RowTemplate`. The renderer clears stale clones, then clones the
  template to `TOP_N` rows **once** (cached) and thereafter **updates text in place + hides
  unused + sets `CanvasSize` to the used count** — so each client's scroll position survives a
  refresh. Top 50 stored, ~15 visible, scroll for the rest (mouse wheel / touch drag, PC +
  mobile). Money via `FormatCash`, playtime via `formatDuration`.
- **Podium** (`PodiumDisplay`): three rigs `PodiumRig1..3` (cloned from `ServerStorage/
  RigTemplate`) on the three pedestals (tallest = 1st). Per refresh, per slot: if the occupant
  **changed**, `ApplyDescription(GetHumanoidDescriptionFromUserId(userId))` (the costly call,
  **gated on change** — pattern from `CharacterService`) with the player's description **scale
  fields overridden by the template's Humanoid scale** (`BodyHeightScale` etc., captured at
  build) so the rig keeps the **editor-authored size**, then re-anchor the root and **re-seat
  the rig feet-on-pedestal from its live bounding box** (robust to the rescale + the template's
  custom pivot); fill the `Nameplate` BillboardGui (**Studio-authored on each rig's
  `HumanoidRootPart`** — survives `ApplyDescription`, so it is restyled in-scene; the renderer
  only writes `NameLabel`/`ValueLabel`) with name + cash; keep the loop
  track playing — **slot 1 walks, slots 2 & 3 idle**. A transient avatar-fetch failure does not
  record the occupant, so the next refresh retries. Empty slots (fewer than 3 ranked) hide the
  rig (parented out). The player-only `Animate` LocalScript is stripped from the template; only
  `HumanoidRootPart` is anchored so the joints can animate while the rig stays put.
- **Tunables** (`shared/LeaderboardConfig.ts`): `REFRESH_INTERVAL`, `TOP_N`, `VISIBLE_ROWS`,
  `ROW_HEIGHT`, `WRITE_SPACING`, store names, `WALK_ANIM_ID`/`IDLE_ANIM_ID`, instance names.

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
| `EndGameStartEvent` | S→C | Start payout animation (baseCash=EffectiveBaseCash, mult, lossMult) — `multRebirth` removed |
| `EndGameFinishedEvent` | C→S | Animation done → server credits money, hides popup |
| `InformationTextEvent` | S→C | Flash info text in HUD (e.g. "Not enough money") |
| `ShopPurchaseEvent` | C→S | Player clicked a cash buy button (arg: `ShopItemId`) |
| `RebirthEvent` | C→S | Player clicked Rebirth (no args) — server validates + resets |

Keep RemoteEvents minimal (per CLAUDE.md). Prefer **player Attributes** for state the
owning client just needs to read (used for `Money`, progression, `AssignedRoom`,
`InSession`). The neon-pipe purchase pulse (§6.12) also uses an attribute as a broadcast
signal — a `Pulse` counter on `NeonPipe/P{n}`, incremented server-side and watched by every
client — instead of a RemoteEvent.

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
| `Safety` cap (shop) | `shared/ShopBalance.ts` | 10 lvls → 50% | Max shop risk reduction (×5% per level) |
| `SAFETY_PASS` | `shared/ShopBalance.ts` | +0.20 | Additional safety from the safety game-pass |
| `SAFETY_TOTAL_CAP` | `shared/ShopBalance.ts` | 0.70 | Hard cap on `AdditionalSecurity` (shop 0.50 + pass 0.20) |
| `COMMUNITY` | `shared/ShopBalance.ts` | group 963505568, ×2 | Group membership ⇒ +1 bonus to `MoneyMult` |
| `MONEY_TIERS` | `shared/ShopBalance.ts` | ×2…×1024, highest owned wins | Game-pass money-tier multipliers; id 0 = inert |
| Rebirth base cost | `shared/ShopBalance.ts` | 2500 | Cash for the 1st rebirth |
| Rebirth cost growth | `shared/ShopBalance.ts` | ×2.4 / rebirth | `cost(R)=floor(2500×2.4^R)` |
| Rebirth mult curve | `shared/ShopBalance.ts` | `[1,2,3,3.5,4,4.5,4.75,5]` +0.25/rebirth | `MultRebirth` factor fed into the additive `MoneyMult` (see §6.6) |
| `REFRESH_INTERVAL` | `shared/LeaderboardConfig.ts` | 60s | Leaderboard/podium refresh period |
| `TOP_N` | `shared/LeaderboardConfig.ts` | 50 | Entries stored/shown per leaderboard |
| `VISIBLE_ROWS` | `shared/LeaderboardConfig.ts` | 15 | Rows visible before scrolling |

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

