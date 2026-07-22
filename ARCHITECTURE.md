# Architecture — Hold or Drop

> Reference document for the codebase. Read this before making structural changes.
> Keep it in sync when systems, services, events, or data flows change.

## 1. Game Concept

**Hold or Drop** is a Roblox risk/reward game. Each player owns a private room with a
button. Holding the button grows a **multiplier** over time, increasing the payout — but
the **explosion risk** also ramps up. The player chooses when to **release** (bank the
cash) or keep **holding** (greed). If the button explodes before the player banks, the run
is lost and pays only a flat fraction of the pot.

Core loop: *enter room → trigger button → hold (multiplier ↑, risk ↑) → release / explode →
end-game payout animation → money credited*.

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
│   │   ├── ShopService, MoneyProductService, ButtonTriggerService, ButtonSessionService, CharacterService, UiService
│   ├── rooms/
│   │   ├── Room.ts          # One room wrapper (parts, ownership, billboard)
│   │   └── RoomService.ts   # player ↔ room assignment
│   ├── modules/
│   │   ├── ButtonModule.ts          # Per-room trigger handler
│   │   ├── ButtonInGameModule.ts    # THE hold/risk/claim game loop
│   │   ├── RocketLauncher.ts        # Per-room rocket flight: launch/stop/reset/explode
│   │   ├── EndGameButtonModule.ts   # Post-game payout + popup coordination
│   │   ├── NeonPipeColors.ts        # Tints Environment/NeonPipe per room occupancy
│   │   ├── ConfettiBurst.ts, CheatConfig.ts
│   ├── UI/
│   │   ├── Popup.ts                 # Base popup (Show/Hide a named Frame)
│   │   ├── PopupConfig.ts           # PopupType → behavior class registry
│   │   ├── PopupBehaviors/          # ButtonMenu / RocketLaunch / ButtonFinishGame
│   │   └── Interface/IPopup.ts
│   └── main.server.ts
├── client/                  # StarterPlayerScripts — visuals, input, camera
│   ├── main.client.ts       # Entry: wires up all client behaviors
│   ├── behaviors/           # ButtonMenu / RocketLaunch / EndGameButton / LossReward / Shop behaviors
│   │   └── ShopBehavior (open/close), ShopItemsController (4 upgrade buttons), ShopMoneyBuyBehavior (Robux money popup)
│   ├── rooms/RoomPromptController.ts  # Per-client ProximityPrompt visibility
│   ├── audio/MusicController.ts  # BGM playlist + high-altitude ascent track
│   └── ui/                  # HUD + effects (MoneyDisplay, InGameUIController, etc.)
└── shared/                  # ReplicatedStorage — code/data used by both sides
    ├── Event.ts             # RemoteEvent catalog (Events namespace)
    ├── Utils/DefineEvent.ts # Creates (server) / waits for (client) a RemoteEvent
    ├── RocketGameConfig.ts  # Shared gameplay tuning constants (risk, multiplier, rocket)
    ├── ResistanceCurve.ts   # Resistance → {riskScale, safeWindow} (partagé serveur/shop)
    ├── AudioConfig.ts       # All sound asset IDs/volumes (music + SFX)
    ├── ShopBalance.ts       # Shop economy numbers (THE rebalancing file)
    ├── ShopConfig.ts        # Shop items + price/value formulas (logic, reads ShopBalance)
    ├── MoneyProducts.ts     # 9 Robux "buy money" dev products (productId ↔ amount)
    ├── PopupType.ts         # Popup enum (shared contract)
    ├── NumberFormat.ts      # FormatCash helper
    └── CameraController.ts  # Camera helper: rocket-follow (Custom) + cinematic (Scriptable)
```

At the repo root, `tools/economy-sim.js` is a dependency-free Node script that reads the
tuning constants straight out of the TypeScript sources above (no copy-pasted numbers) and
simulates runs + shop purchases to assert the design's balance criteria. Run
`node tools/economy-sim.js` (add `--verbose` for a run-by-run breakdown) whenever retuning
the economy — see §6.3/§6.8/§6.9.

## 4. Client / Server / Shared Boundaries

- **Server is authoritative.** All gameplay decisions — risk rolls, explosion, payout,
  ownership validation, persistence — happen on the server. The client never decides
  outcomes; it only sends intent (claim/steer/quit) and renders effects.
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
3. `MoneyProductService` — set `MarketplaceService.ProcessReceipt`; credit `Money` for the 9
   Robux "buy money" developer products (needs PlayerData ready — see §6.15)
4. `PlayerProgressionService` — load/persist the progression **levels** + `Rebirths`, derive
   `BaseCash`, `Multiplier`, `Resistance`, `MultRebirth` (must run before RoomService
   so the `BaseCash` attribute exists at room assignment)
5. `BoostService` — resolve group + game-pass ownership into input attributes (`InCommunity`,
   `MoneyTierMult`, `HasResistancePass`), then call `PlayerProgressionService.recompute` to
   fold them into `MoneyMult` / `EffectiveBaseCash` / `Resistance`; needs
   Progression's `recompute`, runs before `RoomService`
6. `ShopService` — handle cash purchases (needs PlayerData + PlayerProgression ready)
7. `RebirthService` — handle `RebirthEvent`: validate `Money ≥ rebirthCost(Rebirths)`, reset
   `Money` + stat levels, increment `Rebirths` (needs PlayerData + PlayerProgression ready)
8. `LeaderboardService` — global money + playtime rankings (OrderedDataStore) and the podium;
   self-driven 60s refresh loop (needs PlayerData ready — reads `Money`/`Playtime`)
9. `RoomService` — scan `Workspace/PlayerZones`, build rooms, assign players
10. `ButtonTriggerService` — attach a `ButtonModule` to each room (needs rooms built first)
11. `CharacterService` — normalize character scale on spawn
12. `EndGameButtonModule.init()` — wire the payout-finished handshake
13. `PlayerRemoving` → `ButtonSessionService.cleanup` — release session on disconnect

The client (`main.client.ts`) initializes its behaviors/controllers eagerly; most only act
once a server event fires.

## 6. Core Systems

### 6.1 Rooms (`rooms/Room.ts`, `rooms/RoomService.ts`)
- A **Room** wraps one `Workspace/PlayerZones/P{n}` folder containing a `ButtonModel`
  (`ButtonPart` + `ProximityPrompt`, `PlayerPosPlaceHolder`, optional
  `UiPart/BillboardGui/GainText`) and a `MovableModel` (the rocket rig). The rocket body
  itself is **not** authored in the rig — it is instantiated at assign time by `RocketPlacer`
  (§6.18) from `ReplicatedStorage/RocketModels` and pivoted onto the rig's `RocketSpawnPoint`
  marker (an invisible, anchored, non-collidable Part). The rig also holds `CameraParentPart`
  = the rocket-follow camera's `CameraSubject` (see §6.7; `CameraPosPart` is now unused),
  `ParticlesParentPart` holding a disabled `ExplosionParticles` emitter burst on a loss (§6.17),
  and `RocketProximityPromptPart` carrying the rocket's own `ProximityPrompt`), optional
  `CommunityJoinPart`.
  Invalid layouts are skipped with a warning.
- **Ownership is the access rule:** only the assigned occupant may trigger the button.
- `RoomService` assigns the first free room on join (numeric-aware `P1<P2<…<P10` sort),
  releases it on leave, and mirrors the occupant's live **`EffectiveBaseCash`** (not raw
  `BaseCash`) onto the billboard.
- **Community join prompt:** an optional `CommunityJoinPart` sibling of `ButtonModel` — a
  visible `Part` carrying a `ProximityPrompt` **and a `BillboardGui`** ("Rejoindre la communauté
  (×2 argent)"), both globally `Enabled` in Studio (no per-player server toggle; the client
  narrows visibility). The whole flow is **client-driven**.
  **`CommunityJoinController` (client, `rooms/CommunityJoinController.ts`)** mirrors the
  replicated `InCommunity` **and `AssignedRoom`** attributes (client-local writes, same
  per-player trick as `RoomPromptController`/`OwnerIndicatorController`):
  - The `CommunityJoinPart` is shown **only on the player's own room** — every other room's
    **part is made fully transparent** (`Transparency = 1`) and its prompt + billboard disabled,
    so you only ever see the join cue at your own button.
  - On the owned room the prompt is enabled **only while the player is not a member**; once they
    join it is disabled and the billboard's `TextLabel` flips from its Studio CTA ("X2 Money") to
    the claimed badge **"x2 réclamé"** (the billboard stays visible rather than being hidden).
  - **Triggering the prompt opens Roblox's native community-join card** via
    `GroupService:PromptJoinAsync(963505568)` (client-only — the exact card with title, creator,
    member count and emblem rendered by Roblox). On a `Joined`/`AlreadyMember` result the client
    fires **`CommunityJoinedEvent`** (C→S) → `BoostService.refreshCommunity` re-checks membership
    and grants the ×2 (folded into `MoneyMult`, see §6.6), flashing a green
    "Communauté rejointe — x2 argent !" via `InformationTextEvent`.
  - Re-evaluated on spawn and on room (re)assignment.
  > Server-side the re-check uses **`GroupService:GetGroupsAsync`** (a fresh web fetch), NOT
  > `Player:IsInGroup` — the latter is cached for the whole session and would never reflect a
  > join made mid-session, so the ×2 would not land until a rejoin. The re-check is also the
  > **security boundary**: a spoofed `CommunityJoinedEvent` still has to pass `GetGroupsAsync`,
  > so the ×2 is only ever granted to a real member. (`PromptJoinAsync` is live since Dec 2025.)
- **Spawning:** each room folder may hold a spawn marker — a plain `Part` named one of
  `SPAWN_PART_NAMES` (`RespawnLocation`/`SpawnLocation`/`SpawnPart`, resolved in `Room.ts`).
  On assign, `RoomService` connects `player.CharacterAdded` to teleport the occupant onto
  that part on every (re)spawn (and moves an already-present character immediately). A real
  `SpawnLocation` instance is **not** required — matching is by name, placement by teleport.
- `ProximityPrompt.Enabled` is **global** (no per-player toggle), so the server keeps every
  prompt **disabled** and publishes `AssignedRoom` / `InSession` attributes per player.
  `RoomPromptController` (client) enables only the local player's prompts — client-side
  writes don't replicate. Server still validates ownership on `Triggered`. **Each room has
  two prompts wired identically:** the button prompt (`ButtonModel/ButtonPart`) and the
  rocket prompt (`MovableModel/RocketProximityPromptPart`) both start the same game (§6.2),
  and `RoomPromptController` shows/hides them together. The button prompt's `ObjectText`
  shows the cash gain; the rocket prompt keeps its own fixed description ("Launch the rocket").
- **Slot colours** (`modules/RoomColors.ts`): the single source of truth for the per-slot
  palette (P1 blue, P2 red, P3 yellow, P4 green, P5 purple; empty = grey), shared by the
  neon pipes and the spotlights below so the two never drift — **edit here to retune**.
- **Neon pipe colour** (`modules/NeonPipeColors.ts`): each room slot has a matching
  `Workspace/Environment/NeonPipe/P{n}` folder of Neon parts. `RoomService` greys every
  pipe at init (empty baseline), tints a slot's pipe its colour on `assign`, and greys it
  again on `release`.
- **Room spotlight** (`modules/RoomSpotlights.ts`): each room holds a
  `Workspace/PlayerZones/P{n}/Environment/SpotLight` lamp — a Neon `LightSource` lens wrapping a
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
One instance per room. **`bind` connects both the button prompt and the rocket prompt
(`Room.rocketProximityPrompt`, §6.1/§6.17) to the same `onTriggered`** — interacting with
either starts the game. On `Triggered`: validates ownership, guards against double-start
(`InSession` lags one round-trip — re-check the session map), creates the session,
sets `InSession=true`, hides the billboard for the active player, teleports + anchors the
player on the button, fires `ButtonTriggerEvent` to the client (with the room's
`cameraPosPart` + `cameraPivotPart`), and shows the ButtonMenu popup.

> NOTE: `ButtonModule.onTriggered` currently shows the ButtonMenu popup directly but does
> **not** itself call `startButtonGame`. The hold loop is started server-side; trace the
> `StartButtonClickedEvent` wiring when modifying this flow.

### 6.3 The game loop (`modules/ButtonInGameModule.ts`) — the heart
`startButtonGame(player, session)` reads `EffectiveBaseCash` + `Multiplier` once (held for
the session), **launches the rocket** (`RocketLauncher.launch(room)`, see §6.17) and runs
**two independent loops** via `task.spawn`:

- **Multiplier loop** (`MULTIPLIER_TICK_RATE` = 1s): the payout multiplier tracks the rocket's
  **live velocity** — each tick adds `RocketLauncher.getVelocity(room) × MULTIPLIER_TICK_RATE ×
  MULTIPLIER_PER_STUD` (i.e. it grows by the distance the rocket just climbed), starting from
  `STARTING_MULTIPLIER` (1.00). Velocity ramps from 0 and accelerates, so the number is
  near-frozen at liftoff and climbs faster the faster the rocket goes. The rocket's speed is
  scaled by the player's **`RocketSpeed`** stat (read once at session start, passed to
  `RocketLauncher.launch`), so a higher Rocket Speed speeds up the rocket **and** the multiplier
  together — at `RocketSpeed` 1 (level 0, the new-player default) the rocket already reaches
  `ROCKET_MAX_SPEED` (30 studs/s) in 10s (×2.65 multiplier by then), so the first run visibly
  moves the number; each level adds a whole `RocketSpeed` unit, so the first purchase literally
  doubles the ascent and multiplier-climb speed. Drives the `MultiplierText`
  label (formerly `BaseCashText`) in the `RocketLaunch` popup — the client **lerps the shown
  number continuously** between ticks (RenderStepped) so it passes through every intermediate
  value (1.01, 1.02, …) rather than jumping. No floating labels (removed).
- **Risk loop** (`TICK_RATE` = 0.5s): `getRisk(t)` is `MAX_RISK * (t/TOTAL_DURATION)²`
  (EaseInQuad, caps at `MAX_RISK` = 0.8 after `RISK_RAMP_DURATION` = 17s), then reshaped by
  the player's **Resistance** (0..100, read once at session start — see §6.6) via
  `resistanceRiskParams` (`shared/ResistanceCurve.ts`, **not** `ButtonInGameModule.ts`) → a
  `{riskScale, safeWindow}` profile: `riskAt(t)` is `0` while `t ≤ safeWindow`, else
  `getRisk(t − safeWindow) * riskScale`. **`safeWindow` is the primary lever** — it is
  FRONT-loaded (early levels buy most of the guaranteed window, late levels almost nothing)
  and it is what the shop shows the player, in seconds ("Vol garanti", §6.8): L1 ≈ 1.1s,
  L5 ≈ 4.1s, L30 ≈ 7.9s (near-saturated, cap 8s at level 100). `riskScale` is secondary — it
  scales the curve *after* the window, but median survival only grows as `riskScale^(-1/3)`
  (risk has to be halved-then-some, roughly ÷8, to double survival time), so it can't be made
  readable on its own; that asymmetry is why `safeWindow` carries the player-facing message.
  At resistance 0 both terms are neutral → identical to the base curve. The exact explosion
  instant is precomputed once at launch (`rollExplosionTime`, same distribution); each tick
  just refreshes the bar with `riskAt(t)`. Tunables live in `shared/ResistanceCurve.ts`
  (`RESISTANCE_MAX_REDUCTION`, `RESISTANCE_REDUCTION_CURVE`, `RESISTANCE_MAX_SAFE_WINDOW`,
  `RESISTANCE_SAFE_WINDOW_CURVE`).

Every ending **stops + resets the rocket** to its launch pad (`RocketLauncher`, §6.17).

**Claim** (`ClaimButtonEvent`, replaces the old instant "release"): pressing `ClaimButton`
**locks in** the current multiplier as a guaranteed win but the **rocket does NOT stop** — it
keeps flying (the `MultiplierText` keeps climbing on screen, now purely cosmetic) until it
explodes. The server captures `claimedMultiplier = currentMultiplier` and fires
`ClaimAcceptedEvent(claimedMultiplier)`. On claim the `ClaimButton` turns red (the explosion
colour), plays the **cash SFX** (`AudioConfig.sfx.moneyGain`, not the generic UI click — the
button carries a `NoUiClick` attribute so `UiClickSound` skips it), and is disabled (no
double-claim). The strategic tension is now *claim before the rocket explodes*: claim too late
and the explosion lands first (loss); claim in time and the explosion just collects your
locked win.

**Go Home** (`GoHomeEvent`): `CLAIM_REARM_DELAY` (0.6 s) after a claim the **same button
re-arms**, with its side label (`ClaimButtonFrame.TextLabel`) swapped from `"Claim"` to
`"Go Home"` (the button's own text is empty and stays so) and its **original colour restored**
(the claim red means "not clickable"; it is clickable again). Clicking it ends the run
**immediately** instead of waiting for the explosion: the server stops the rocket in place
(`RocketLauncher.stop`), pays the **same locked gain**
`floor(EffectiveBaseCash × claimedMultiplier)` through the normal EndGame popup path
(`enter(mode="released")`), and fires `GameResultEvent(exploded=false)` so the client hands
the camera back to the player — the exact "return home" of an explosion, minus the
explosion. On the click the client also kills **every flight effect at once**
(`resetPostProcess(true)`: camera shake, bloom, FOV) plus the run music and the steering —
the shake decay lives in the `isGameActive`-gated RenderStepped loop, so a leftover
amplitude would otherwise stay frozen on the camera after it returns to the player. `GO_HOME_RESET_DELAY` (0.6 s) later, once the camera has left the pad,
`RocketLauncher.reset` + `RocketPlacer.place` respawn a **fresh rocket** on the pad, same as
after an explosion. The server **refuses
`GoHomeEvent` before a claim** (it would be a free escape from the risk), and both the
explosion branch and the client's `PlayerKilledEvent` handler cancel the re-arm, so an
explosion during those 0.6 s wins.

**`ResultMultiplierText`** (a `RocketLaunch` label) is a **live "cash-out preview"**: it shows
the money you'd bank if you claimed right now — `floor(EffectiveBaseCash × displayedMultiplier)`,
formatted `"{n}$"` (`FormatNumber`). The client reads `EffectiveBaseCash` once per run (replicated
attribute) and refreshes the label in the RenderStepped loop, **throttled** — only when the
multiplier has moved ≥ `RESULT_UPDATE_MULT_STEP` (0.01) **and** ≥ `RESULT_UPDATE_MIN_DELAY`
(0.2 s) since the last refresh. On claim it snaps immediately to the locked value
(`floor(EffectiveBaseCash × claimedMultiplier)`, matching the server payout exactly) and freezes.

Endings:
- **Claimed → rocket explodes:** guaranteed win. The rocket bursts (`RocketLauncher.explode` +
  3D boom + `PlayerKilledEvent` orbit-on-blast), then after `EXPLOSION_VIEW_DELAY`
  `RocketLauncher.reset` + `RocketPlacer.place` swap in a fresh rocket and the **full** payout
  `floor(EffectiveBaseCash * claimedMultiplier)` runs → EndGame (`lossMultiplier=1`).
- **Claimed → player hits "Go Home":** same guaranteed win, collected early. No explosion:
  `RocketLauncher.stop` freezes the rocket, `GameResultEvent(exploded=false)` returns the
  camera, the payout `floor(EffectiveBaseCash * claimedMultiplier)` runs → EndGame
  (`mode="released"`, `lossMultiplier=1`), and after `GO_HOME_RESET_DELAY`
  `RocketLauncher.reset` + `RocketPlacer.place` respawn a fresh rocket on the pad.
- **Explosion roll hits before any claim (loss):** fire `ButtonExplodedEvent` (client stops the
  run music, kills the bloom and closes the run — the claim can no longer lock anything), then
  the **rocket explodes, not the player** — `RocketLauncher.explode` bursts the
  `ExplosionParticles` in the rocket's `ParticlesParentPart` + a 3D boom; **no `Explosion`
  instance, no fling, no death, no movement freeze**. The client (`PlayerKilledEvent`) keeps the
  orbit camera on the exploding rocket for `EXPLOSION_VIEW_DELAY` (impact FOV punch + shake)
  before swinging back, then `RocketLauncher.reset` snaps the rig back to the pad and
  **`RocketPlacer.place` swaps in a brand-new rocket** (the exploded one is destroyed, not
  reassembled). A loss pays **no ButtonFinishGame popup**: instead a **flat consolation
  `floor(EffectiveBaseCash / 3)`** (`LOSS_CONSOLATION_DIVISOR`, **no multiplier** — holding
  longer doesn't raise it) is granted via `EndGameButtonModule.enterRewardOnly` →
  `LossRewardEvent`, shown client-side by `LossRewardBehavior` as a single "+amount" text that
  jumps then flies into the money HUD (§6.4). (No `Humanoid.Health=0` / Motor6D disable
  anymore.) The `ClaimButton` does **not** disappear on a loss — it turns red and
  `Interactable=false` (reset to normal at the next launch). There is **no pre-explosion
  "cling" sound** (removed).

> All payout paths are floored and use `EffectiveBaseCash` — the rebirth multiplier and all
> boosts are already folded into it (see §6.6). `EffectiveBaseCash` is read once at session start
> so a mid-run boost change can't affect an in-progress hold. A **claimed** run pays the locked
> `claimedMultiplier` (captured at claim time, so the EndGame popup uses that exact value);
> a **loss** pays a flat `EffectiveBaseCash / 3` **with no multiplier at all** (a longer,
> greedier hold you then lose is worth no more than a short one). There is no separate
> `MultRebirth` factor at payout time. The old grace-period "release to cancel" is gone (the
> button now claims, not releases).

The 3D boom (`playExplosionSoundAt`, used by both the claimed and the lost explosion) is cloned
from a **pre-buffered ReplicatedStorage template** to avoid a CDN fetch at runtime. No
`Explosion` instance is ever created — the burst is purely the rocket's particles.

### 6.4 End game (`modules/EndGameButtonModule.ts`)
`enter(...)` cleans up the session, stashes `pendingEarned`, then (after a delay or
respawn) shows the `ButtonFinishGame` popup and fires `EndGameStartEvent`
`(baseCash=EffectiveBaseCash, multiplier, lossMultiplier)` to drive the client payout
animation — the payload already carries the final credited amount so the animation matches
exactly. `multRebirth` was removed from the payload; the client animation no longer has a
gold rebirth phase. The client signals `EndGameFinishedEvent` when the animation ends →
server credits `Money` and hides the popup.
**Money is credited only after the client animation completes** (single source of truth).
- `enterRewardOnly(player, reward)` is the **losing-explosion** path (§6.3): no popup — it
  cleans up the session, hides the `RocketLaunch` popup, stashes `reward` in the **same
  `pendingEarned` map**, and fires `LossRewardEvent(reward)`. The client (`LossRewardBehavior`)
  re-enables the HUD, jumps a single "+reward" text into the money display, then fires the
  **shared** `EndGameFinishedEvent` on arrival → the same handler credits `reward` and the HUD
  counter reconciles with no jump. One new server→client event, and no duplicate credit logic.

### 6.5 Popups (`UI/Popup.ts`, `UI/PopupConfig.ts`, `services/UiService.ts`)
- `PopupType` enum (`shared/PopupType.ts`): `ButtonMenu`, `RocketLaunch`, `ButtonFinishGame`.
  (The `RocketLaunch` popup — formerly `ButtonInGame` — holds the live `MultiplierText`, the
  `ClaimButtonFrame/ClaimButton`, and the `ResultMultiplierText` — a live "if you claim now"
  cash-out preview (`"{n}$"`) that throttles as the multiplier climbs and freezes on claim
  (§6.3); the old `Slider`/progress-bar was removed.)
- Server `PopupConfig` maps each type to a behavior class; `UiService` shows/hides by type
  and tracks one current popup per player (showing a new one hides the previous).
- A popup resolves `PlayerGui/InGameUI/<className>` Frame and toggles `Visible`.
- Client mirrors this with `PopupBehaviors/` + `behaviors/` that animate the frames.

### 6.6 Persistence (`PlayerDataService`, `PlayerProgressionService`)
- Both follow the same pattern: **DataStore-backed, mirrored to player Attributes** so the
  owning client can read state directly via replication.
- `PlayerDataService` → `Money` **and `Playtime`** (total seconds played, accumulated across
  sessions; defaults 0 for existing saves — no version bump) (store `PlayerData_v1`).
- `PlayerProgressionService` → stores the **levels** `BaseCashLevel`, `RocketSpeedLevel`,
  `ResistanceLevel` **and the `Rebirths` count** (store `PlayerProgression_v2`). The effective
  values `BaseCash`, `RocketSpeed`, `Resistance` are **derived** from the levels, and
  `MultRebirth` is derived from `Rebirths`, all via `shared/ShopConfig` and mirrored to
  attributes (levels, values, `Rebirths` and `MultRebirth` all replicate). Storing levels/count
  means the curves can be retuned later with **zero save migration** — and `Rebirths` is a new
  field that defaults to 0 for existing saves (no version bump). The old `SafetyLevel` key was
  renamed to `ResistanceLevel` (no version bump): existing saves have no `ResistanceLevel`, so
  those players simply start at Resistance 0 — acceptable since Resistance resets every rebirth.
  - **Derived boost attributes** (`deriveValues` / `recompute`): `MoneyMult` and
    `EffectiveBaseCash` are also derived and mirrored to attributes on every recompute.
    `MoneyMult` **multiplies the rebirth factor by an additive boosts factor**
    (`shared/ShopConfig.moneyMult`): `MoneyMult = MultRebirth × (1 + (InCommunity ?
    COMMUNITY.mult−1 : 0) + (MoneyTierMult−1))`. Rebirth multiplies because it is the
    long-term progress axis; community/game-pass boosts add *inside* that factor so a ×2
    pass stays worth ×2 at any rebirth level — a purely additive model would let a large
    `MultRebirth` swamp the boosts (a ×2 pass on top of ×4096 would add a negligible +1) and
    make them unsellable. `EffectiveBaseCash = floor(BaseCash × MoneyMult)` — this is the value used by the
    billboard, HUD, and payout (§6.3).
    `Resistance` folds in the resistance pass (flat bonus LEVELS):
    `Resistance = min(shopResistance + (HasResistancePass ? RESISTANCE_PASS.addLevels : 0), 100)`.
- **`BoostService`** resolves the three live input attributes each session (not persisted,
  no DataStore key, no migration needed):
  - `InCommunity` — `true` if the player is a member of group `963505568`; re-checked
    server-side via `BoostService.refreshCommunity` when the player uses `CommunityJoinPart`.
  - `MoneyTierMult` — the multiplier of the highest money-tier game-pass the player owns
    (table `MONEY_TIERS` in `shared/ShopBalance.ts` — ids configured ×2…×1024); defaults to 1.
  - `HasResistancePass` — `true` if the player owns the resistance game-pass (id 0 = inert).
  After writing these attributes `BoostService` calls `PlayerProgressionService.recompute`
  so `MoneyMult` / `EffectiveBaseCash` / `Resistance` update immediately.
  - **Game-pass ownership is a per-player SET** of owned ids, seeded once on join (real
    `UserOwnsGamePassAsync`, or the `CheatConfig` simulation — §9) and updated **directly**
    from `PromptGamePassPurchaseFinished` using the purchased id (then `recount` → `recompute`).
    It must **not** re-query `UserOwnsGamePassAsync` after a purchase: that call caches per
    session (and a Studio test purchase never grants real ownership), so re-querying returns
    the pre-purchase value and the boost would silently never apply. `devOwn` / `devDisown` /
    `devReset` (server — callable from the command bar / `execute_luau`) mutate the set via the
    same `recount` path for testing.
- `rebirth(player)` (the only rebirth mutation) resets the 3 stat levels to 0 and increments
  `Rebirths`, re-deriving every value. It does **not** touch `Money` — `RebirthService` zeroes
  that via `PlayerDataService` so each service owns its own store.
- **Safe-save guard:** only players whose load succeeded are added to `loadedPlayers` and
  thus eligible to save — a transient load failure never wipes progress.
- `BindToClose` saves all players in parallel within the ~30s shutdown budget.
- `get/set/add(player, key, …)` are the public accessors. Bump `STORE_NAME` (`_v2`) to wipe
  everyone. **API Services must be enabled** in Studio for DataStores to work.

> `Resistance` (0..100, sold as **Resistance** in the shop + optionally boosted by the
> resistance game-pass) reshapes the explosion risk: the risk loop reads it once at session
> start and maps it to a `{riskScale, safeWindow}` profile (see §6.3). The cap is 100 =
> shop 100 (+ pass levels, clamped).

### 6.7 Camera & HUD (client)
- `CameraController` (shared): `SetCinematic` (Scriptable), `AnimateTo` (tween CFrame),
  `BringBackPlayerCamera` (return the camera to the player + reset to Custom).
  - **Rocket follow camera** (`StartOrbit(posCFrame, subjectPart)` / `StopOrbit`): the
    button/rocket flow uses the **default Roblox camera** (`CameraType.Custom`) with its
    `CameraSubject` pointed at `CameraParentPart` instead of the player's Humanoid. The player
    keeps native camera controls (rotate/zoom on all platforms), and because the MovableModel
    carries `CameraParentPart` up with it, the camera **follows the rocket** as it climbs with
    no per-frame code. On the switch to the rocket the zoom is snapped to a dezoomed distance
    (`ROCKET_VIEW_DISTANCE`, framing the rocket + a bit of the room); on the return to the
    player it snaps back to `DEFAULT_VIEW_DISTANCE` — both via a one-tick
    `CameraMin/MaxZoomDistance` pin that is then released so the player keeps free zoom
    (`snapZoomDistance`). `posCFrame` is unused (the native camera owns positioning) — the
    parameter is kept so the call site stays unchanged. Started by `ButtonMenuBehavior` on
    `ButtonTriggerEvent`, it persists through the hold; `BringBackPlayerCamera` hands the
    subject back to the player's Humanoid on quit/release/death (tweening only when returning
    from a `Scriptable` cinematic). The shake (Camera±1 bindings) layers on top of the native camera's
    `Camera`-priority CFrame with no change. The rocket body parts (the placed `Rocket` model) are set
    `CanQuery = false` in `RocketLauncher` so the camera's occlusion raycasts ignore them and
    never pull the camera into the rocket.
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
  earnings cancel and restart from the current visual value. The fill only renders once
  progress reaches a minimum displayable X-scale (`MIN_VISIBLE_PROGRESS` = 0.013); below that
  the `CurrentProgressionFrame` is hidden (`Visible = false`) instead of showing an unreadable
  sliver, and at/above it the fill is clamped to that minimum width.
  earnings cancel and restart from the current visual value.
- `MoneyBoostController` (`behaviors/MoneyBoostController.ts`): drives the readout
  `HUD/BottomList/ProgressionBar/MoneyBoostText` off the replicated `MoneyTierMult` attribute
  (the highest owned money-tier game-pass multiplier, resolved by `BoostService` — see §6.6).
  `MoneyTierMult > 1` → `"{mult}x money boost"`, visible; `MoneyTierMult == 1` (no money-tier
  pass owned) → hidden. Refreshes on the attribute change; client-side display only.
- **Persistent GUI:** `InGameUI.ResetOnSpawn = false` is set directly on the ScreenGui in
  Studio so it survives death/respawn. `main.client.ts` additionally sets
  `StarterGui.ResetPlayerGuiOnSpawn = false` as a player-wide safety net. Client behaviors
  cache their UI references once at startup; without this guard, respawning would wipe
  `PlayerGui`, destroy the cached `startButton`/`quitButton`/etc., and silently break
  ButtonMenu et al. (subsequent `Activated.Connect` calls would land on dead instances).
- `RocketLaunchBehavior` owns the heavy game-feel: Bloom and a two-binding camera-shake
  design (restore clean CFrame at Camera-1, apply shake at Camera+1) to avoid spring drift.
  The launch shake is **strong at liftoff** (`LAUNCH_SHAKE_START`) and **decays toward 0**
  each frame (`LAUNCH_SHAKE_DECAY`, in the RenderStepped count-up loop) — like climbing out of
  the atmosphere into calm space. The stronger `MAX_SHAKE_AMPLITUDE` is only the
  explosion-impact punch. There is **no red vignette / ColorCorrection** and **no progressive
  FOV zoom** during the climb (both removed); FOV is only touched for the explosion punch and
  the reset. It listens to all the server gameplay events and translates them into effects.
  It also owns a **client-only onboarding pulse** on the Claim button (`startClaimPulse` /
  `stopClaimPulse`): a looping size + `UIStroke` breathing tween nudges a new player toward
  claiming, and it stops for good after `CLAIM_PULSE_RUNS` (3) claims in the session
  (`sessionClaimCount`, a plain client-local counter — no server state, no persistence, resets
  on rejoin).

### 6.8 Shop (`shared/ShopConfig.ts`, `server/services/ShopService.ts`, `client/behaviors/ShopItemsController.ts`)
- The shop sells three upgrades from `Workspace/Shop` (ProximityPrompt → `InGameUI/ShopMenu`,
  open/close handled by `ShopBehavior`). Four buttons map to the upgrades:
  `AButtonMoney` = BaseCash +1, `BX5ButtonMoney` = BaseCash +5, `CRocketSpeed` = RocketSpeed +1,
  `DSafety` = Resistance +1 (the Studio frame is still named `DSafety`; only the code stat and
  the player-facing title changed to Resistance).
- **`ShopBalance` (shared)** holds every tunable economy number (start prices, per-stat price
  growth, value growth, Resistance cap, rebirth cost/mult growth) and nothing else — **the
  file to edit when rebalancing**. (The Resistance→risk *curve* constants live in
  `shared/ResistanceCurve.ts`, not here — see §6.3.)
- **`ShopConfig` (shared)** is the structure + logic, fed by `ShopBalance`: `ITEMS`, per-stat
  `STATS` (value attribute, level attribute, `startPrice`, per-stat `priceGrowth`, optional
  `maxLevel`, `valueFor`, `display`) and pure pricing helpers — `priceForLevel` =
  `floor(start * priceGrowth^level)` (each stat carries its **own** `priceGrowth` field — there
  is no shared growth constant across stats; the three stats multiply together in the payout,
  so one common growth rate would let the economy run away), `priceForItem` (strict sum of the
  next N levels), `isAtCap`. Imported by both sides so prices/stat previews computed on the client
  always match the server.
  - Curves: BaseCash `floor(100 * 1.2^level)`, RocketSpeed `1 + level` (integer, uncapped),
    Resistance `level` (plain integer, `maxLevel` 100). Start prices **50 / 75 / 150**
    (BaseCash / RocketSpeed / Resistance), price growth **1.8 / 1.7 / 1.35** per stat — a
    steep wall on the two money-scaling stats, a gentle one on Resistance so it offers many
    small, affordable steps (it resets every rebirth). The RocketSpeed value scales the
    rocket's ascent (and thus the multiplier) — see §6.3 / §6.17. The Resistance *value* is
    just the level; its non-linear effect on risk is applied in the risk loop (§6.3) via
    `shared/ResistanceCurve.ts`, not in the stat curve.
- **`ShopService` (server)** owns the **cash** mutation path. On `ShopPurchaseEvent` it validates
  the item id, checks the cap, re-checks `Money >= price`, then `PlayerDataService.add(-price)`
  + `PlayerProgressionService.addLevel`. Rejections flash `InformationTextEvent`. The client
  pre-check is UX-only; the server never trusts it. On success it also fires the neon-pipe
  purchase pulse for the buyer's room (`NeonPipeColors.pulse`, see §6.12). The **Robux** path
  (level dev products on the RobuxButtons) is the other mutation path — handled by
  `MoneyProductService.ProcessReceipt`, see §6.15.
- **`ShopItemsController` (client)** binds the four frames. For each it renders current→next
  **impact**, not the raw stat value (`BoostLyout/CurrentStatText` → `NextStatText`, via each
  stat's `display` in `ShopConfig.STATS`) and the cash price (`BuyButton/TextLabel`), greys
  unaffordable buttons, shows `MAX` at the Resistance cap, and fires `ShopPurchaseEvent`. The
  per-stat display: BaseCash shows the **effective** `$` gain (`floor(value * MoneyMult)`, so it
  already reflects rebirth/boosts); RocketSpeed shows the raw speed plus the multiplier it
  reaches at `SPEED_PREVIEW_SECONDS` (10s), e.g. `"3 (x6.0)"`; Resistance (frame `DSafety`,
  titled **"Vol garanti"**) shows the guaranteed flight seconds from
  `resistanceRiskParams(value).safeWindow`, e.g. `"4.1s"` — the only readable framing of that
  stat (§6.3). It
  **also wires each frame's `RobuxButton`** to the matching level dev product
  (`shared/LevelProducts.ts`, resolved by the frame's stat): sets the gain label
  (`GainQuantityText` = `"+{levels} niv."`) + the Robux price (`RobuxQuantityText` via cached
  `GetProductInfo`) and prompts `MarketplaceService:PromptProductPurchase` on click. The
  Resistance RobuxButton is **refused at the cap** — no prompt, just an `InformationText` "Niveau
  maximum atteint" (and the button greys with `MAX`). It refreshes purely from replicated
  attributes (`Money` + the three level attributes) — no server→client response event.
- **Multiplier readout** (`ShopMenu/Header/MultiplierText`): displays the current `MoneyMult`
  and its breakdown as `Money ×T (Rebirth ×R × Boosts ×B)` — `T` = `MoneyMult`, `R` =
  `MultRebirth`, `B` = the additive community + money-tier factor (`1 + …`, see §6.6) — so the
  player can see the multiplicative-rebirth / additive-boosts split at a glance.
- **`BoostShopController` (client)**: now **read-only** — it just drives the multiplier readout
  above (refreshing on `MoneyMult` / `MultRebirth` / `MoneyTierMult` / `InCommunity`). The shop
  RobuxButtons it used to wire (`AButtonMoney` money-tier upsell, `DSafety` resistance pass) were
  repurposed for the level dev products (see `ShopItemsController` above); the money-tier
  game-pass upsell now lives only on the HUD `MultiplierBuyButton` (`MultiplierPassController`).
- **`MultiplierPassController` (client)** — the HUD "buy multiplier pass" button
  (`HUD/BottomList/MultiplierBuyButton`), separate from the shop. Offers the next unowned
  `MONEY_TIERS` pass via `nextMoneyTier(MoneyTierMult)`: writes
  `BuyMultiplierPassFrame/RewardText` = `"{mult}x Money"` and `…/CostMovingText/CCCostText`
  = the pass's **raw** Robux price (`GetProductInfo`, cached per id, no K/M formatting); its
  sibling `TextButton` prompts `PromptGamePassPurchase`. Refreshes on `MoneyTierMult` change
  (a purchase advances it to the next pass); once every tier is owned the whole button is
  hidden (`Visible = false`). `CostTextRotator` (`ui/CostTextRotator.ts`) gives the
  `CostMovingText` frame a constant cosmetic wobble.
### 6.9 Rebirth (`server/services/RebirthService.ts`, `client/behaviors/RebirthMenuBehavior.ts`, `client/behaviors/RebirthMenuController.ts`)
A permanent money multiplier earned by resetting everything. It lives in its **own panel**
(`InGameUI/RebirthMenu`), **independent of the shop** — opened from the HUD button
`InGameUI/HUD/ButtonsFrame/RebirthFrame/ImageButton`, closed via `RebirthMenu/CloseFrame/CloseButton`.
- `ShopConfig` exposes the pure pricing/reward: `rebirthCost(R) = floor(20 000 × 38^R)` and
  `rebirthMult(R) = 8^R` (geometric — no lookup table). `multGrowth` = 8 is calibrated so a
  player recovers their pre-rebirth peak income in ~3 runs (they restart with all 3 stat
  levels at 0); `costGrowth` = 38 deliberately outpaces that, so rebirth cycles lengthen
  progressively (R1 ≈ 5 min, R4 ≈ 8 min, R7 ≈ 16 min) instead of staying flat.
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
  `SafeRebirthButton/Button` (a Robux "keep all your progression" variant) prompts the safe-rebirth
  developer product — **no in-game money gate** (it's a paid convenience). The grant is server-side
  via `RebirthService.safeRebirth` (see §6.15): +1 `Rebirths` while **Money AND stat levels are kept**,
  then the pad rocket is swapped to the new level. The menu refreshes on the `Rebirths` attribute
  change like any other rebirth.
- **`RebirthService` (server)** re-validates (`Money ≥ rebirthCost`) and performs the reset —
  never trusts the client. After rebirth `MultRebirth` grows, which feeds into `MoneyMult` and
  therefore `EffectiveBaseCash` (re-derived by `PlayerProgressionService.recompute` — see §6.6).
  It then **swaps the pad rocket immediately** via `RocketPlacer.place` on the player's room
  (§6.18), so the new rebirth-level rocket appears at once. **`Playtime` is never touched by the
  rebirth path** — it is the leaderboard's playtime source (§6.14) and must survive every rebirth.
  - **Cancel in-flight payout on rebirth:** a run whose end-game payout / loss-reward floating
    texts are still flying toward the money HUD (§6.4) would otherwise credit money **after** the
    reset to 0. So a normal rebirth also calls **`EndGameButtonModule.cancelPending`** (clears the
    player's `pendingEarned` and hides the finish popup, so a late `EndGameFinishedEvent` credits
    nothing) and fires **`RebirthResetEvent`** (S→C) → client **`FloatingCash`** (`client/ui/FloatingCash.ts`)
    destroys the in-flight floating frames and bumps a generation so their arrival callbacks no-op.
    **Safe rebirth does neither** — it keeps Money, so an in-flight payout must still land.

### 6.10 Audio (`shared/AudioConfig.ts`, `client/audio/MusicController.ts`, `client/audio/UiClickSound.ts`)
- **`AudioConfig` (shared)** is the single registry of every sound asset (id + volume):
  the BGM `playlist`, the `highAltitude` ascent track, and the `sfx` (server `explosion` +
  `rocketLaunch` (looped 3D engine roar — see §6.17),
  client `buttonUpgrade` / `moneyGain` / `uiClick`; `buttonExplode` is still defined
  but no longer played — the pre-explosion "cling" cue was removed). SFX still play
  from their existing call sites (`RocketLaunchBehavior` client-side, `ButtonInGameModule`
  server-side, `NeonPipePulse` for `buttonUpgrade` — see §6.12, `MoneyDisplay` for `moneyGain`,
  `UiClickSound` for `uiClick`) — only the asset definitions are centralised here, so
  re-pointing a sound is a one-line edit.
- **`moneyGain`** (2D, client) plays the instant money is banked in the HUD:
  `MoneyDisplay.addVisual` clones a preloaded template on every positive deposit, so during the
  end-game payout it fires once per landing chunk (§6.4 / EndGameAnimation) — synced to the
  count-up, no offset. It is **also** played by `RocketLaunchBehavior` on **claim** (its own
  preloaded template) as the button's cash sound (§6.3).
- **`UiClickSound` (client, `audio/UiClickSound.ts`)** centralises the `uiClick` button sound:
  on init it hooks every `GuiButton` descendant of `PlayerGui` — those present at start **and**
  any added later (`DescendantAdded`) — connecting `Activated` to a 2D clone of a preloaded
  template (`hooked` set guards against double-binding). A button whose **`NoUiClick`** attribute
  is `true` is skipped (checked at click time, so the attribute can be set after hooking) — used
  by the `ClaimButton`, which plays the cash SFX instead. Any new button authored in Studio gets
  the click sound automatically, with no per-button wiring.
- **Music is client presentation** (see §4). `MusicController` (client) owns two things,
  parented to `SoundService`:
  - **BGM**: a looping playlist played through the **new audio API** so a spectrum can be read
    for the visualiser (§6.11): an `AudioPlayer` → `AudioFader` → `AudioDeviceOutput` (audible)
    plus a `Wire` branch from the **player** (before the fader) to an `AudioAnalyzer`
    (`SpectrumEnabled`, `WindowSize` Medium). A single track loops via `Looping`; multiple tracks
    advance on `Ended` and wrap back to the first. Started in `main.client.ts`. The base BGM
    **plays through the whole ascent** (no more duck at hold start): `startRun()` just makes sure
    the high-altitude track is stopped and the `AudioFader.Volume` is at full. The fader ducks only
    at two moments — the **altitude crossfade** and the **explosion cut** — and the player's own
    `Volume` stays constant, so the analyzer (tapped before the fader) keeps reading the full
    spectrum and the **visualiser keeps running through the run**. On any run end `resumeBgm` eases
    the base BGM back in slowly (3s) once the run is fully over — on **respawn** (death path, via
    `CharacterAdded`) or at the **end of the payout animation** (survive path, fired from
    `EndGameButtonBehavior`). `resumeBgm` is a no-op unless ducked; a single stored tween is
    cancelled before each new fade. `getBgmAnalyzer()` exposes the analyzer to the visualiser
    (client-only — `GetSpectrum` returns empty server-side).
  - **High-altitude music**: a **classic `Sound`** (looped), created + preloaded at init (no CDN
    stall on the first crossfade). `RocketLaunchBehavior` captures the rocket's Y at launch (the
    camera's `CameraSubject` **is** the rocket part during a run) and, once it has climbed
    `HIGH_ALTITUDE_MUSIC_THRESHOLD` (50) studs, calls `enterHighAltitude()` **once per run** — which
    crossfades: `AudioFader.Volume` → 0 while the high track fades in (0.8s). At the explosion,
    `stopRunMusic()` hard-cuts the high track and quickly ducks the base BGM to 0 (0.25s) so the run
    ends on silence, then `resumeBgm` brings the base BGM back. Called on `ButtonExplodedEvent`
    (unclaimed loss) and on `PlayerKilledEvent` (claimed win / loss, which has
    no `ButtonExplodedEvent`). `startRun` / `stopRunMusic` / `resumeBgm` are all idempotent.

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
  leaves the live list), `NeonPipePulse` fires a one-shot: it enables the electric
  `ParticleEmmiter.UpgradeButtonParticles` emitter for `PARTICLE_DURATION` (1.2 s) then disables
  it, and plays a 3D electric SFX (`AudioConfig.sfx.buttonUpgrade`, a `Sound` created client-side
  once and parented to `ButtonPart`). The emitter now lives on the **rocket**
  (`PlayerZones/P{n}/MovableModel/ParticleEmmiter`, moved from the button), while the sound stays
  on `PlayerZones/P{n}/ButtonModel/ButtonPart`. Both are resolved once in `buildRoomState` and
  cached on the `RoomState`; either may be absent (e.g. a room whose package lacks the emitter)
  and is then skipped.
  Overlapping arrivals are handled by a `particleToken` so only the latest 1.2 s timer disables
  the emitter. The emitter sits **disabled** at rest in Studio; its holder part is anchored /
  non-collidable. 100 % client (every client animates the replicated `Pulse`, so all see it).
  - **Rocket reaction shake:** the same arrival also gives the **`MovableModel`** a brief soft
    **X+Z jitter** (`advanceShake`): a damped sine oscillation over `SHAKE_DURATION` (≈0.4 s,
    amplitude ≈0.25 studs) so the rocket — at rest on its pad — visibly reacts to the upgrade,
    then settles back. Applied via `PivotTo` as a **delta** (sums to zero → no drift), advanced
    inside the existing `RenderStepped` loop, and the room stays active until the shake settles.
    Client-only presentation (the rocket is never mid-flight during a purchase, since the owner is
    at the shop, not holding the button). Tunables at the top of `NeonPipePulse.ts`:
    `SHAKE_DURATION`, `SHAKE_AMPLITUDE`, `SHAKE_FREQUENCY_X/Z`.
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

**Held poses vs one-shots.** `playInteract`/`playHold` play their clip once then **freeze it on
the last frame** (a `Heartbeat` watcher pins `AdjustSpeed(0)` just before the natural end so the
non-looped track can't auto-stop). Only one held pose at a time (`currentHold`). `playQuit`/
`playRelease` are fire-and-forget one-shots **not** tracked, so they blend back to
Roblox's defaults on their own and a later `stop()` never cuts them short. `stop()` drops only
the held pose; `restoreDefault()` stops everything (held + in-flight one-shot) to force defaults.
Tracks are lazily loaded against the current `Animator` and the cache is dropped on respawn.
Call sites: `ButtonMenuBehavior` (`playInteract` on `ButtonTriggerEvent`, `playQuit` on Quit);
`RocketLaunchBehavior` (`playHold` in `setup`, `stop` on `GameResultEvent` as a safety net — the
character keeps the hold pose through a claim, since claiming no longer releases the button);
`EndGameButtonBehavior` (`restoreDefault` on `EndGameStartEvent` — the payout popup opening ends
any still-playing release clip).

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

### 6.15 Developer products (`shared/MoneyProducts.ts`, `shared/LevelProducts.ts`, `shared/RebirthProducts.ts`, `server/services/MoneyProductService.ts`, `client/behaviors/ShopMoneyBuyBehavior.ts`, `client/behaviors/ShopItemsController.ts`)
Three families of Robux developer products, all routed through one `ProcessReceipt`:
- **Money packs** — Robux "buy money" packs sold from the **`InGameUI/ShopMoneyBuy`** popup
  (separate from the upgrade `ShopMenu`, §6.8). Nine packs, opened from the HUD's
  `MoneyParent/PlusButton/TextButton`.
- **Progression products** — 3 products sold on the upgrade `ShopMenu` **RobuxButtons** (§6.8):
  BaseCash +10 levels (on both the +1 and +5 frames), RocketSpeed +10 levels, Resistance +1 level.
- **Safe rebirth** — 1 product sold on the Rebirth menu's `SafeRebirthButton` (§6.9): a paid
  rebirth that **keeps all progression** (Money + stat levels) and only grows the permanent
  multiplier. `shared/RebirthProducts.ts` holds the id (`SAFE_REBIRTH_PRODUCT_ID`) +
  `isSafeRebirthProduct(id)` lookup, shared by the client prompt and the server grant.

- **`MoneyProducts` (shared)** — single source of truth for the money packs: an **ordered** list
  of the 9 `{ productId, amount }` pairs. Index *i* maps to `Body/MoneyElement{i+1}`; `amount`
  mirrors each element's `ValueText` (250 → 100M). The Robux price is set per product on the
  Roblox dashboard (the `CostText` label is display-only). `amountForProduct(id)` is the
  server-side lookup.
- **`LevelProducts` (shared)** — single source of truth for the progression products: a list of
  `{ productId, stat, levels }`. `levelGrantForProduct(id)` is the server-side lookup;
  `levelProductForStat(stat)` the client-side one (so both BaseCash frames resolve to the same
  product via their shared stat). Robux price is configured per product on the dashboard.
- **`ShopMoneyBuyBehavior` (client)** — open/close + purchase prompts for the money popup (mirrors
  `ShopBehavior`): starts the popup hidden; `PlusButton/TextButton` opens it (hides the HUD via
  `InGameUIController.disable`), `Header/CloseButtonFrame/CloseButton` closes it (restores the HUD);
  each `MoneyElement{n}/Button` fires `MarketplaceService:PromptProductPurchase(player, productId)`.
  The progression products are prompted by `ShopItemsController` instead (§6.8).
- **`MoneyProductService` (server)** — owns the game's single `MarketplaceService.ProcessReceipt`
  (route any future developer products through it). On a receipt it looks the product up in **both**
  families: a money pack credits the mapped `amount` via `PlayerDataService.add(player, "Money", …)`;
  a progression product adds `levels` to its stat via `PlayerProgressionService.addLevel` (the
  `addLevel` clamp handles the Resistance cap — a max-level buy still grants but the client prevents
  prompting at the cap); the safe-rebirth product delegates to `RebirthService.safeRebirth` (+1
  `Rebirths`, keeps Money + levels, swaps the pad rocket — §6.9). Each path returns `PurchaseGranted`;
  it returns `NotProcessedYet` (Roblox retries) when the buyer isn't in-game or their data is still
  loading (the relevant attribute — `Money` for packs, the stat's level for progression, `Rebirths`
  for safe rebirth — is unset), so a grant is never lost nor written over a fresh load. The grant is a
  synchronous attribute write immediately followed by the return — no double-grant window, so no
  DataStore receipt log is needed. (The safe-rebirth rocket swap is wrapped in `pcall` so a cosmetic
  failure after the increment can't turn the granted receipt into a retry — see `RebirthService`.)

### 6.16 Community mascot idle (`client/rooms/CommunityMascotController.ts`)
Cosmetic hover **and** per-player visibility for the community mascot — the
`GrorianStudioMascot` MeshPart sits **directly in each room folder**
(`PlayerZones/P{n}/GrorianStudioMascot`, a sibling of `CommunityJoinPart`). 100 % client /
presentation, no server logic. Discovery is streaming-aware (`WaitForChild`/`ChildAdded` down
`PlayerZones → P{n} → GrorianStudioMascot`, re-registering on stream-in) like the other room
controllers. The mascot is anchored, so a single looping `TweenService` Position tween
(`FLOAT_HEIGHT` 1 stud, `FLOAT_DURATION` 2 s, Sine in/out, reversing, `RepeatCount -1`) renders
cleanly client-side; a small random phase keeps the rooms from bobbing in lockstep.
- **Per-room visibility:** like the `CommunityJoinPart` elements (§6.1 / `CommunityJoinController`),
  the mascot is shown **only on the player's own room** — every other room's mascot is made fully
  transparent (`Transparency = 1`, the Studio default captured per entry so it's reversible). Driven
  by the replicated `AssignedRoom` attribute (client-local write, re-applied on room (re)assignment
  and on each stream-in).

### 6.17 Rocket launch (`server/modules/RocketLauncher.ts`)
Server-driven rocket flight for a room's `MovableModel`. **Single source of truth** (replicates
to everyone, ties to the server-side game loop), no RemoteEvent. The rocket body it drives is the
child Model named **`Rocket`** (the stable name `RocketPlacer` renames every placed rocket to, see
§6.18) — exported as `ROCKET_MODEL`. Because the rocket is swapped per occupant, `RocketPlacer`
calls **`clearRocketCache(room)`** on each (re)placement to drop the per-room caches (pad pivot,
captured body parts, launch sound, active flight) that referenced the destroyed model; they are
recaptured on the next `launch`.
- **`launch(room, speedFactor=1)`** — captures the model's launch-pad pivot once (per room),
  resets to it, then a `RunService.Heartbeat` loop ramps `velocity` from 0 by `ROCKET_ACCEL`
  up to `ROCKET_MAX_SPEED` and rises the model via `PivotTo` each frame (slow, accelerating,
  real-rocket feel). `ROCKET_ACCEL`/`ROCKET_MAX_SPEED` are **per Rocket-Speed unit** (3 / 30);
  `speedFactor` is the player's **`RocketSpeed`** stat value, so actual accel/max = value × those
  (value 1 = level 0's default, reaches 30 studs/s in 10s; value 6 = accel 18 / max 180).
  **`getVelocity(room)`** exposes the live
  velocity (0 if not flying) — the game loop's multiplier tick reads it so the payout multiplier
  tracks the rocket's speed (§6.3).
- Moving the **whole `MovableModel`** carries `CameraPosPart` / `CameraParentPart` up with it, so
  the client orbit camera (reads the pivot live, §6.7) **follows the rocket** with zero extra code.
- **Steering (up-axis flight):** the ascent loop moves the rocket along **its own up-axis**, not
  world-Y. A per-room roll angle `tilt` is integrated each frame from the player's steering intent
  (`setSteer(room, dir)`, `dir` = -1/0/+1) at a rate that **ramps with altitude** — near-zero at the
  pad (`STEER_ROT_SPEED_GROUND`), full once the rocket reaches space (`STEER_ROT_SPEED_SPACE` at
  `STEER_SPACE_HEIGHT` studs). The roll is **uncapped** (accumulates freely). The orientation is
  `basePivot.Rotation × CFrame.Angles(0,0,-tilt)` (roll about the forward axis; the `-tilt` inverts
  the steer direction) and the model climbs along `orientation.UpVector`, so a roll makes it **drift
  sideways**; releasing input **holds** the current tilt (no auto-centre). Because authority is ~0 low down, the rocket stays centred in the room shaft and only
  becomes steerable in open sky. `getVelocity` stays the **scalar** speed, so steering **never**
  touches the payout multiplier. The intent comes from the client's **native movement** input
  (`RocketSteerController` reads Roblox's ControlModule `GetMoveVector().X` — keyboard/thumbstick/
  gamepad, all devices; the character is anchored during a run so movement doesn't walk it) and is
  sent via **`RocketSteerEvent`** only when it changes; `ButtonInGameModule` resolves the player's
  room and forwards it. `setSteer` is a no-op when the room isn't flying.
- **Engine fire:** `launch` lights **every** engine emitter (`Fire`/`ParticleEmitter`/`Smoke`)
  inside the rocket's `NitroParticles` part(s); `stop`/`reset` extinguish them — so the nitro burns
  only while the rocket is moving. A rocket may carry **several** `NitroParticles` parts (multi-engine
  rockets, e.g. Lvl4/Lvl5 have 5 each), now authored as **direct children of the rocket model**;
  `setNitroEnabled` iterates the whole `MovableModel` so it toggles them all. The **at-rest off**
  state is enforced by `RocketPlacer` (§6.18) when it clones the rocket — the templates' authored
  `Enabled` is inconsistent, so it no longer matters.
- **Launch sound:** `launch` also plays a **looped 3D** "engine roar"
  (`AudioConfig.sfx.rocketLaunch`) — a `Sound` created once per room and parented to the
  `NitroParticles` engine part (so it emanates from the rocket and rises with it; server-authored
  like the explosion boom so every nearby client hears it). It is stopped in **`stopRoom`** — the
  common chokepoint of `stop`/`reset`/`explode` — so it cuts on every ending: explosion, claim
  (release) and quit. (`LAUNCH_SOUND_ROLLOFF` at the top of `RocketLauncher.ts`.)
- **`stop(room)`** halts the ascent in place; **`reset(room)`** halts + snaps back to the pad
  (called on every ending, §6.3); **`explode(room)`** bursts the `ExplosionParticles` emitter in
  the rocket's `ParticlesParentPart` (authored disabled in Studio, like `UpgradeButtonParticles`)
  **and physically breaks the rocket apart** (see below).
- The rocket parts are all **anchored** (no PrimaryPart needed — `PivotTo` uses the model pivot).
  `RocketPlacer` force-anchors every body part of the placed rocket (some `RocketModels` templates
  ship with unanchored parts that would otherwise fall — see §6.18). The non-body helpers
  (`CameraPosPart`, `CameraParentPart`, `ParticlesParentPart`, `RocketProximityPromptPart`,
  `RocketSpawnPoint`) are anchored + non-collidable too, so they ride with the rig and never fall
  — `explode` only unanchors the `Rocket` body parts.
  `startButtonGame` launches it; the loss path (§6.3) explodes it; the win/quit paths reset it.
- **Physical explosion (loss path).** `explode` unanchors every body part of the `Rocket`
  model (the `Camera*`/`ParticlesParentPart` helpers stay anchored so the orbit camera keeps
  holding on the blast site), flings each one outward with a **horizontal-only radial spread**
  (X/Z, so the burst never pushes a part down) plus a **height-scaled upward kick** (lowest part
  lifts by `BURST_UP_MIN`, the nose by `BURST_UP_MAX` — every part is launched up, never any -Y
  burst velocity) and a random spin, then runs a Heartbeat applying **height-based gravity**:
- **Physical explosion (loss path).** `explode` first reads the rocket's current ascent speed
  then **halts the ascent loop itself** (the loss path no longer pre-calls `stop`), so the speed
  survives to be inherited. It unanchors every body part of the `Rocket` model (the
  `Camera*`/`ParticlesParentPart` helpers stay anchored so the orbit camera keeps holding on the
  blast site), and flings each one **radially outward from the rocket centre** with an upward
  bias, a random spin, **and the inherited ascent momentum** — so the rocket **keeps climbing as
  it breaks apart** until gravity bleeds the momentum off. It then runs a Heartbeat applying
  **height-based gravity**:
  weightless above `SPACE_HEIGHT` (world-Y 95, "space"), gravity fading in through the 95→50
  band, full earth gravity below `GROUND_HEIGHT` (50). It cancels the appropriate fraction of
  `Workspace.Gravity` each frame (`+gravity*(1-scale)` upward → net pull `gravity*scale`) rather
  than using `VectorForce` instances. Debris is `CanCollide=false` while flying so it can't snag
  on geometry. `launch` captures each body part's **pad-relative pose + authored CanCollide once**
  (`captureRocketParts`); `reset` (`restoreRocketParts`) disconnects the debris loop, zeroes
  velocities, re-anchors, restores collision, and re-poses every part to `padPivot * offset` — so
  the next launch starts from a pristine rocket no matter how the debris scattered. Tunables at
  the top of `RocketLauncher.ts`: `SPACE_HEIGHT`, `GROUND_HEIGHT`, `BURST_SPEED`,
  `BURST_SPEED_VARIANCE`, `BURST_UP_MIN`, `BURST_UP_MAX`, `BURST_SPIN`.

### 6.18 Rocket selection & placement (`server/modules/RocketPlacer.ts`)
Chooses and instantiates the rocket that sits on a room's pad, matched to the occupant's
**rebirth level**. The rocket bodies are authored in **`ReplicatedStorage/RocketModels`** as
`RocketLvl1..RocketLvlN` (currently 5); none lives in the rig by default — `RocketPlacer.place(room)`
clones the right one onto the rig's `RocketSpawnPoint` (§6.1).
- **Level mapping:** `level = clamp(Rebirths, 1, N_rockets)` — `Rebirths` directly indexes the
  rocket level; rebirth 0 falls back to `RocketLvl1` (there is no Lvl0) and any rebirth count above
  the number of rockets gets the highest one. (Read via `PlayerProgressionService.getRebirths`.)
- **Placement:** removes any rocket already on the pad, calls `RocketLauncher.clearRocketCache(room)`
  (rooms are reused across occupants — see §6.17), then clones the template, renames it to the stable
  **`Rocket`** (`ROCKET_MODEL`), **force-anchors every body part** (some templates ship with
  unanchored parts that would otherwise fall), parents it to the `MovableModel`, and moves its pivot
  by the delta to **`RocketSpawnPoint`**'s position (orientation kept as authored — the marker's
  position is authoritative, no ground-snapping/bounding-box correction).
- **Trigger / async load:** `RoomService.assign` calls it via `placeRocketWhenReady`. Because
  `PlayerProgressionService` loads `Rebirths` asynchronously, the attribute may still be nil at
  assign; if so the placement is deferred until the attribute first appears (a one-shot
  `GetAttributeChangedSignal`, cleaned up on leave). It's also called by `ButtonInGameModule` on a
  **loss** (rocket explosion) — after `RocketLauncher.reset(room)` snaps the rig back to the pad,
  `RocketPlacer.place(room)` destroys the exploded rocket and clones a fresh one, so the occupant
  never sees the blown-apart debris reassemble itself. Release/quit endings just `reset`
  (no explosion happened, so the same rocket instance is fine). Finally, `RebirthService`
  (§6.9) calls it after a successful rebirth — the `Rebirths` count just changed, so the pad
  rocket is swapped **instantly** for the new level rather than lingering until the next room
  (re)assignment.
- **Authoring note:** only `RocketLvl1`/`RocketLvl2` currently carry a `NitroParticles` engine part,
  so Lvl3–Lvl5 launch without an engine flame (no error — the launcher just finds no `Fire`); add a
  `NitroParticles` part (with a `Fire`) to those templates to restore the effect.

## 7. Networking — Event Catalog (`shared/Event.ts`)

`DefineEvent` creates the `RemoteEvent` on the server and `WaitForChild`s it on the client,
parented to the `Event` ModuleScript. Direction noted per event:

| Event | Dir | Purpose |
|-------|-----|---------|
| `ButtonTriggerEvent` | S→C | Start menu flow; passes `cameraPosPart` + `cameraPivotPart` (orbit camera) |
| `StartButtonClickedEvent` | C→S | Player clicked Start |
| `ClaimButtonEvent` | C→S | Player claimed — lock in the current multiplier (rocket keeps flying) |
| `GoHomeEvent` | C→S | Post-claim "Go Home" — stop the rocket and end the run now (refused before a claim) |
| `QuitButtonClickedEvent` | C→S | Player quit the menu |
| `RocketSteerEvent` | C→S | Native left/right movement redirected to the flying rocket (dir -1/0/+1, sent on change) |
| `ClaimAcceptedEvent` | S→C | Confirms a claim with the authoritative locked multiplier |
| `ButtonExplodedEvent` | S→C | Explosion roll hit without a claim — client closes the run (music + bloom) |
| `PlayerKilledEvent` | S→C | Loss — rocket exploded; client lingers the camera on it then restores (no death anymore) |
| `MultiplierUpdateEvent` | S→C | New current multiplier (client lerps `MultiplierText` continuously to it) |
| `RiskUpdateEvent` | S→C | Current risk value |
| `GameResultEvent` | S→C | (exploded, earned, multiplier) — re-enable HUD |
| `EndGameStartEvent` | S→C | Start payout animation (baseCash=EffectiveBaseCash, mult, lossMult) — `multRebirth` removed |
| `EndGameFinishedEvent` | C→S | Animation done → server credits money, hides popup |
| `InformationTextEvent` | S→C | Flash info text in HUD (e.g. "Not enough money") |
| `ShopPurchaseEvent` | C→S | Player clicked a cash buy button (arg: `ShopItemId`) |
| `RebirthEvent` | C→S | Player clicked Rebirth (no args) — server validates + resets |
| `CommunityJoinedEvent` | C→S | Native join card returned Joined/AlreadyMember — server re-checks (GetGroupsAsync) + grants ×2 |

Keep RemoteEvents minimal (per CLAUDE.md). Prefer **player Attributes** for state the
owning client just needs to read (used for `Money`, progression, `AssignedRoom`,
`InSession`). The neon-pipe purchase pulse (§6.12) also uses an attribute as a broadcast
signal — a `Pulse` counter on `NeonPipe/P{n}`, incremented server-side and watched by every
client — instead of a RemoteEvent. Robux purchases also use **no** RemoteEvent: game-pass
upsells go through `MarketplaceService:PromptGamePassPurchase` (§6.8), and the developer
products (money packs + progression products) through `PromptProductPurchase` + `ProcessReceipt`
(§6.15).

## 8. Gameplay Tuning Constants

| Constant | Location | Value | Meaning |
|----------|----------|-------|---------|
| `RISK_RAMP_DURATION` | `shared/RocketGameConfig.ts` | 17s | Risk/progress full ramp |
| `MULTIPLIER_TICK_RATE` | `shared/RocketGameConfig.ts` | 1s | Multiplier tick interval |
| `STARTING_MULTIPLIER` | `shared/RocketGameConfig.ts` | 1 | Base payout multiplier (start) |
| `MULTIPLIER_PER_STUD` | `shared/RocketGameConfig.ts` | 0.01 | Multiplier gained per stud the rocket climbs (velocity-driven) |
| `ROCKET_ACCEL` | `shared/RocketGameConfig.ts` | 3 | Rocket acceleration per RocketSpeed unit (studs/s²), ×stat value |
| `ROCKET_MAX_SPEED` | `shared/RocketGameConfig.ts` | 30 | Rocket top speed per RocketSpeed unit (studs/s), ×stat value |
| `STEER_ROT_SPEED_GROUND` | `shared/RocketGameConfig.ts` | rad(4)/s | Roll rate at the pad — extremely weak |
| `STEER_ROT_SPEED_SPACE` | `shared/RocketGameConfig.ts` | rad(30)/s | Roll rate in space — responsive |
| `STEER_SPACE_HEIGHT` | `shared/RocketGameConfig.ts` | 50 | Studs above pad where roll authority reaches full |
| `EXPLOSION_VIEW_DELAY` | `shared/RocketGameConfig.ts` | 1.5s | Camera lingers on the exploding rocket before restoring |
| `MAX_RISK` | `ButtonInGameModule.ts` | 0.8 | Risk ceiling |
| `TICK_RATE` | `ButtonInGameModule.ts` | 0.5s | Risk-loop interval |
| `RESISTANCE_MAX_REDUCTION` | `shared/ResistanceCurve.ts` | 0.75 | Risk floor at Resistance 100 (×0.25) — secondary lever |
| `RESISTANCE_REDUCTION_CURVE` | `shared/ResistanceCurve.ts` | 13 | ↑ = more front-loaded `riskScale` reduction |
| `RESISTANCE_MAX_SAFE_WINDOW` | `shared/ResistanceCurve.ts` | 8s | Guaranteed no-explosion head start at Resistance 100 |
| `RESISTANCE_SAFE_WINDOW_CURVE` | `shared/ResistanceCurve.ts` | 14 | ↑ = more front-loaded `safeWindow` — the primary lever (§6.3) |
| `LOOSE_WIN_MULTIPLIER` | `ButtonInGameModule.ts` | 0.3 | Payout factor on loss (rocket explodes) |
| `EXPLOSION_BLAST_RADIUS` | `ButtonInGameModule.ts` | 12 | Scoped blast/fling |
| Default `BaseCash` / `RocketSpeed` | `PlayerProgressionService.ts` | 100 / 1 | New-player progression (level 0) |
| Value curves (BaseCash / RocketSpeed) | `shared/ShopBalance.ts` | ×1.2 per level / +1 per level | BaseCash exponential; RocketSpeed integer linear |
| Price growth (per stat) | `shared/ShopBalance.ts` | ×1.8 / ×1.7 / ×1.35 per level | BaseCash / RocketSpeed / Resistance — each stat has its own `priceGrowth`, no shared constant |
| Shop start prices | `shared/ShopBalance.ts` | 50 / 75 / 150 | BaseCash / RocketSpeed / Resistance lvl 1 |
| `Resistance` cap (shop) | `shared/ShopBalance.ts` | 100 lvls | Max resistance level (risk curve in §6.3) |
| `RESISTANCE_PASS` | `shared/ShopBalance.ts` | +20 lvls | Bonus resistance levels from the resistance game-pass (id 0 = inert) |
| `COMMUNITY` | `shared/ShopBalance.ts` | group 963505568, ×2 | Group membership ⇒ +1 bonus to the boosts factor, which is then MULTIPLIED by `MultRebirth` to form `MoneyMult` |
| `MONEY_TIERS` | `shared/ShopBalance.ts` | ×2…×1024, highest owned wins | Game-pass money-tier multipliers (ids configured; sold via shop upsell + HUD MultiplierBuyButton) |
| Rebirth base cost | `shared/ShopBalance.ts` | 20 000 | Cash for the 1st rebirth |
| Rebirth cost growth | `shared/ShopBalance.ts` | ×38 / rebirth | `rebirthCost(R)=floor(20 000×38^R)` |
| Rebirth mult growth | `shared/ShopBalance.ts` | ×8 / rebirth | `rebirthMult(R)=8^R` (geometric, no lookup table) — the `MultRebirth` factor that MULTIPLIES the additive boosts factor in `MoneyMult` (see §6.6) |
| `REFRESH_INTERVAL` | `shared/LeaderboardConfig.ts` | 60s | Leaderboard/podium refresh period |
| `TOP_N` | `shared/LeaderboardConfig.ts` | 50 | Entries stored/shown per leaderboard |
| `VISIBLE_ROWS` | `shared/LeaderboardConfig.ts` | 15 | Rows visible before scrolling |

## 9. Cheats (`modules/CheatConfig.ts`)

Dev-only flags — **must be `false`/disabled before publishing**:
- `invincible` — button never explodes.
- `resetData` — wipe persisted data on join (fresh default profile each time).
- `ignoreGamePasses` — when on, `BoostService` seeds every player with an empty owned-pass set
  on join, so you start exactly like a player who never bought any game pass even on an account
  that owns every pass. Takes priority over `simulateGamePasses` (§6.6).
- `simulateGamePasses` + `simulatedOwnedPassIds` — when on, `BoostService` ignores real
  game-pass ownership and treats only the listed ids as owned (empty = own nothing), so the
  buy flow can be tested from a not-owned state even on an account that owns every pass (§6.6).

## 10. Conventions (see also `CLAUDE.md`)

- Strong typing; avoid `any`. Prefer simple, readable, single-responsibility files.
- Don't rewrite working systems; modify only what the task needs (CLAUDE.md refactoring rules).
- Server authoritative; keep client/server responsibilities separate.
- Absolute imports from `src/` (`server/…`, `client/…`, `shared/…`).
- Comments may be EN or FR (codebase is mixed); match the surrounding file.
- Mobile players supported by default; consider performance.
```

