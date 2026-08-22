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
│   │   ├── QuestService          # quêtes + ScrollToken (§6.26)
│   │   ├── ScrollShopService     # dépense des ScrollToken (§6.27)
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
│   │   └── QuestsBehavior        # panneau des quêtes, 2 onglets (§6.26)
│   │   └── ScrollShopController  # boutique ScrollToken (§6.27)
│   ├── rooms/RoomPromptController.ts  # Per-client ProximityPrompt visibility
│   ├── audio/MusicController.ts  # BGM playlist + high-altitude ascent track
│   └── ui/                  # HUD + effects (MoneyDisplay, InGameUIController, MoneyBurst, etc.)
└── shared/                  # ReplicatedStorage — code/data used by both sides
    ├── Event.ts             # RemoteEvent catalog (Events namespace)
    ├── Utils/DefineEvent.ts # Creates (server) / waits for (client) a RemoteEvent
    ├── RocketGameConfig.ts  # Shared gameplay tuning constants (risk, multiplier, rocket)
    ├── ResistanceCurve.ts   # Resistance → {riskScale, safeWindow} (partagé serveur/shop)
    ├── AudioConfig.ts       # All sound asset IDs/volumes (music + SFX)
    ├── ShopBalance.ts       # Shop economy numbers (THE rebalancing file)
    ├── ShopConfig.ts        # Shop items + price/value formulas (logic, reads ShopBalance)
    ├── MoneyProducts.ts     # 9 Robux "buy money" dev products (productId ↔ amount)
    ├── DailyRewardConfig.ts # Daily reward: streak → multiplier, day boundary, 3X product
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
8. `DailyRewardService` — daily streak → `DailyMultiplier` / `DailyClaimed` /
   `DailyAutoOpen` attributes + the claim grant (§6.25). Needs PlayerData (streak keys +
   `Money`) and PlayerProgression (`EffectiveBaseCash`, `isFirstSession`) ready
9. `QuestService` — quêtes + ScrollToken (§6.26) : progression, versement de la
   récompense et publication des attributs `Q_<id>` / `QR_<id>`. Needs PlayerData ready
   (crédite `ScrollTokens` par le même chemin que `Money`)
10. `LeaderboardService` — global money + playtime rankings (OrderedDataStore) and the podium;
   self-driven 60s refresh loop (needs PlayerData ready — reads `Money`/`Playtime`)
11. `AnalyticsService` — official Roblox analytics wrapper (§6.19); logs the onboarding funnel
   join step. Needs PlayerProgression ready (reads `isFirstSession` for the onboarding gate)
12. `RoomService` — scan `Workspace/PlayerZones`, build rooms, assign players
13. `ButtonTriggerService` — attach a `ButtonModule` to each room (needs rooms built first)
14. `CharacterService` — normalize character scale on spawn
15. `EndGameButtonModule.init()` — wire the payout-finished handshake
16. `MegaRocketService` — horloge de l'événement Mega Rocket (§6.24). After `RoomService` — it
    re-places the on-pad rockets the moment the event fires
17. `ScrollShopService` — dépense des ScrollToken (§6.27). Après `MegaRocketService`
    (il appelle `fireNow`) et PlayerData / PlayerProgression (débit + effets)
18. `PlayerRemoving` → `ButtonSessionService.cleanup` — release session on disconnect

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
  and `ParticlesParentPart` holding a disabled `ExplosionParticles` emitter burst on a loss (§6.17)),
  optional `CommunityJoinPart`.
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
  `RoomPromptController` (client) enables only the local player's prompt — client-side
  writes don't replicate. Server still validates ownership on `Triggered`. The room's single
  button prompt (`ButtonModel/ButtonPart`) starts the game (§6.2), and its `ObjectText`
  shows the cash gain.
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
One instance per room. **`bind` connects the button prompt to `onTriggered`.** On
`Triggered`: validates ownership, guards against double-start
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

- **Multiplier loop** (`MULTIPLIER_TICK_RATE` = 0.25s): the payout multiplier tracks the rocket's
  **live velocity** — each tick adds `RocketLauncher.getVelocity(room) × MULTIPLIER_TICK_RATE ×
  MULTIPLIER_PER_STUD` (i.e. it grows by the distance the rocket just climbed), starting from
  `STARTING_MULTIPLIER` (1.00). Velocity ramps from 0 and accelerates, so the number is
  near-frozen at liftoff and climbs faster the faster the rocket goes. The rocket's speed is
  scaled by the player's **`RocketSpeed`** stat (read once at session start, passed to
  `RocketLauncher.launch`), so a higher Rocket Speed speeds up the rocket **and** the multiplier
  together — at `RocketSpeed` 1 (level 0, the new-player default) the rocket reaches
  `ROCKET_MAX_SPEED` (30 studs/s) in 10s; each level adds a whole `RocketSpeed` unit, so the
  first purchase literally doubles the ascent and multiplier-climb speed. `MULTIPLIER_PER_STUD`
  (0.0061) is calibrated against the **7s average flight** (below) for a **×1.50 average
  multiplier**: ×1.24 at 5s, ×1.46 at 7s, ×1.94 at 10s, ×2.85 at 15s. Note the velocity cap at
  10s puts most of the long tail in the *linear* part of the curve, which flattens the jackpot —
  `ROCKET_MAX_SPEED` is the lever if a rarer-but-bigger top end is wanted. The 0.25s tick keeps
  the payout tracking the real flight length instead of jumping a whole step per 0.1s. Drives
  the `MultiplierText`
  label (formerly `BaseCashText`) in the `RocketLaunch` popup — the client **lerps the shown
  number continuously** between ticks (RenderStepped) so it passes through every intermediate
  value (1.01, 1.02, …) rather than jumping. No floating labels (removed).
- **Flight duration** — drawn **once at launch**, in one shot, from a **log-normal**
  distribution (`rollExplosionTime`); there is no per-tick risk roll and no hazard curve any
  more. It is a Gaussian bell laid on a *multiplicative* time scale ("4s ×÷1.4") rather than an
  additive one ("4s ±1.2s"): same sharp peak, same collapse of probability as you move away,
  but it can never produce a zero or negative duration and its long side stays open, which is
  what keeps a jackpot run possible. An additive bell is closed on both sides — holding the low
  tail above zero forces the high tail shut, and the ×5 run stops existing at all. Two knobs:
  `FLIGHT_TIME_MEAN` (4s at Resistance 0) and `FLIGHT_TIME_SIGMA` (0.35, the width). The median
  is derived as `MEAN · e^(−σ²/2)` so **tuning σ does not move the mean** — σ is the single
  "how unpredictable is this game" dial. Sampling is Box–Muller over two `math.random()` draws,
  clamped to `[FLIGHT_TIME_MIN, FLIGHT_TIME_MAX]` = 0.1s..60s (safety rails, not gameplay
  bounds).
  Reference points at Resistance 0: median 6.58s, mean 7.00s, 68% of flights in 4.7–9.3s, 95%
  in 3.3–13.0s, observed ceiling ~33s. Multiplier side: mean ×1.50, median ×1.40, p95 ×2.21,
  a ×3 every ~185 runs (a ×5 is effectively out of reach at level 0 — see the multiplier loop).
- The draw is reshaped by the player's **Resistance** (0..100, read once at session start —
  see §6.6) via `resistanceRiskParams` (`shared/ResistanceCurve.ts`, **not**
  `ButtonInGameModule.ts`) → a `{riskScale, safeWindow}` profile, which moves and widens the
  bell without changing its proportions:
  - `safeWindow` is **added** to the draw, so the shop's "Vol garanti X s" promise (§6.8) holds
    literally whatever the dice say. It is the **primary lever**, and it is the sum of two
    terms — that split *is* the balance of the stat:
    - a FRONT-loaded **burst** (`RESISTANCE_SAFE_WINDOW_BURST` = 5s,
      `RESISTANCE_SAFE_WINDOW_CURVE` = 9): ~**+0.5s per level at the start** (L1 +0.52s,
      L5 +0.40s, L10 +0.29s), fading out over the first ~20 levels. A steady climb the
      player feels level after level, not one big step on L1-L3;
    - a **linear** term (`RESISTANCE_SAFE_WINDOW_LINEAR` = 9s): a flat **+0.09s per level,
      L1→L100, that never saturates**. This is what keeps mid and late levels worth buying —
      every purchase moves the number printed on the shop card.
  - `riskScale` **multiplies the median** by `riskScale^(-1/3)`. On a multiplicative scale
    stretching the median stretches the whole bell, so its shape is identical at every level.
    Secondary lever and **BACK-loaded** (`RESISTANCE_REDUCTION_CURVE` = 1.2, i.e. a power of
    `n`, not of `1-n`): negligible before L20, it takes over at the far end where the burst is
    long spent. Risk has to be cut roughly ÷8 to double the duration, which is why
    `safeWindow` carries the player-facing message.
  At Resistance 0 both terms are neutral. Guaranteed seconds / mean flight: L0 0/7.0s,
  L1 0.5/7.5s, L2 1.0/8.0s, L5 2.3/9.3s, L10 4.0/11.0s, L20 6.1/13.3s, L50 9.5/17.0s,
  L100 14.0/22.5s. Marginal gain per level never drops below ~0.09s (it hit 0.00s past L30
  before this pass). Tunables live in `shared/ResistanceCurve.ts`
  (`RESISTANCE_MAX_REDUCTION`, `RESISTANCE_REDUCTION_CURVE`, `RESISTANCE_SAFE_WINDOW_BURST`,
  `RESISTANCE_SAFE_WINDOW_CURVE`, `RESISTANCE_SAFE_WINDOW_LINEAR`).
- The **risk loop** (`TICK_RATE` = 0.5s) no longer rolls anything: it just paces the run and
  clamps its last step to the drawn deadline so the explosion fires exactly on time.

Every ending **stops + resets the rocket** to its launch pad (`RocketLauncher`, §6.17).

**Claim** (`ClaimButtonEvent`, replaces the old instant "release"): pressing `ClaimButton`
**locks in** the current multiplier as a guaranteed win but the **rocket does NOT stop** — it
keeps flying (the `MultiplierText` keeps climbing on screen, now purely cosmetic) until it
explodes. The server captures `claimedMultiplier = currentMultiplier` (raw — the claim
bonuses below never touch it) plus `claimedBaseCash = EffectiveBaseCash × claimBonus`, and
fires `ClaimAcceptedEvent(claimedMultiplier, perfect, critical, claimedBaseCash)`. On claim the `ClaimButton` turns red (the explosion
colour), plays the **cash SFX** (`AudioConfig.sfx.moneyGain`, not the generic UI click — the
button carries a `NoUiClick` attribute so `UiClickSound` skips it), and is disabled (no
double-claim). The strategic tension is now *claim before the rocket explodes*: claim too late
and the explosion lands first (loss); claim in time and the explosion just collects your
locked win. On `ClaimAcceptedEvent` the client also fires the **cash burst**
(`MoneyBurst.play()`, §6.21) alongside the locked-gain popup.

**Perfect Claim** (`shared/RocketGameConfig.ts`): claiming in the **last instants before the
scheduled explosion** multiplies the locked gain by `PERFECT_CLAIM_MULTIPLIER` (**×3**). The
server compares the real flight time (`os.clock() - launchClock`, frame-accurate — the risk
loop only advances by `TICK_RATE` steps) with the explosion deadline: `remaining ≤
perfectClaimWindow(deadline)` ⇒ perfect. The window is `PERFECT_CLAIM_WINDOW` (0.5 s) on a
short flight and **widens proportionally past `PERFECT_CLAIM_REFERENCE_TIME`** (7 s) —
`0.5 × deadline/7`, capped at `PERFECT_CLAIM_MAX_WINDOW` (1.5 s) — so a long, less predictable
flight isn't a harder timing test than a short one (30 s flight ⇒ 1.25 s window). The deadline
is read **before** `scripted.onClaim()` (the tutorial rewrites it, which would otherwise hand
out a free perfect), and `invincible` (deadline ∞) never triggers it. The ×3 is applied to
the **base cash**, not the multiplier: `claimedBaseCash = EffectiveBaseCash × 3`, and every
payout path multiplies that by the untouched `claimedMultiplier` — the total is identical to
folding the ×3 into the multiplier, but the player can see *which* value the bonus grew.
`ClaimAcceptedEvent(multiplier, perfect, critical, claimedBaseCash)` carries the
flag (no new RemoteEvent); the client only **latches** it and flashes the red
`PERFECT CLAIM  BASE CASH ×3` text (§6.22) later, on `PlayerKilledEvent` — i.e. **on the explosion**,
which is what validates the coup on screen. (A Perfect Claim followed by a "Go Home" —
possible only in the widened-window case, since the button re-arms after
`CLAIM_REARM_DELAY` 0.6 s — pays the ×3 without the flash: there is no explosion.)
Analytics logs an extra `PerfectClaim` counter.

**Critical Claim** (`shared/RocketGameConfig.ts`): every claim also rolls a plain die —
`CRITICAL_CLAIM_CHANCE` (**5 %**) to multiply the locked gain by `CRITICAL_CLAIM_MULTIPLIER`
(**×10**). No timing, no skill: pure surprise. The roll happens server-side in the same
`ClaimButtonEvent` handler and is **independent of the Perfect Claim** — both factors simply
multiply (`claimBonus = 3 × 10` = ×30 on the rare double). Like the ×3, the bonus multiplies
the **base cash** (`claimedBaseCash`), never `claimedMultiplier`, so no payout path knows
about it. The `critical` flag rides the same `ClaimAcceptedEvent`, and unlike the perfect flag
the client shows its golden `CRITICAL CLAIM  BASE CASH ×10` flash + icon rain **immediately, on the claim**
(§6.22/§6.23) — nothing about it depends on the explosion. Analytics logs a `CriticalClaim`
counter.

**Go Home** (`GoHomeEvent`): `CLAIM_REARM_DELAY` (0.6 s) after a claim the **same button
re-arms**, with its side label (`ClaimButtonFrame.TextLabel`) swapped from `"Claim"` to
`"Go Home"` (the button's own text is empty and stays so) and its **original colour restored**
(the claim red means "not clickable"; it is clickable again). Clicking it ends the run
**immediately** instead of waiting for the explosion: the server stops the rocket in place
(`RocketLauncher.stop`), pays the **same locked gain**
`floor(claimedBaseCash × claimedMultiplier)` through the normal EndGame popup path
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
(`floor(claimedBaseCash × claimedMultiplier)` — `claimedBaseCash` comes straight from
`ClaimAcceptedEvent`, so it matches the server payout exactly) and freezes.

Endings:
- **Claimed → rocket explodes:** guaranteed win. The rocket bursts (`RocketLauncher.explode` +
  3D boom + `PlayerKilledEvent` orbit-on-blast), then after `EXPLOSION_VIEW_DELAY`
  `RocketLauncher.reset` + `RocketPlacer.place` swap in a fresh rocket and the **full** payout
  `floor(claimedBaseCash * claimedMultiplier)` runs → EndGame (`lossMultiplier=1`).
- **Claimed → player hits "Go Home":** same guaranteed win, collected early. No explosion:
  `RocketLauncher.stop` freezes the rocket, `GameResultEvent(exploded=false)` returns the
  camera, the payout `floor(claimedBaseCash * claimedMultiplier)` runs → EndGame
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
> `claimedMultiplier` (captured at claim time, so the EndGame popup uses that exact value)
> applied to `claimedBaseCash` = `EffectiveBaseCash × claimBonus` (Perfect/Critical, §6.3);
> a **loss** pays a flat `EffectiveBaseCash / 3` **with no multiplier at all** (a longer,
> greedier hold you then lose is worth no more than a short one). There is no separate
> `MultRebirth` factor at payout time. The old grace-period "release to cancel" is gone (the
> button now claims, not releases).

The 3D boom (`playExplosionSoundAt`, used by both the claimed and the lost explosion) is cloned
from a **pre-buffered ReplicatedStorage template** to avoid a CDN fetch at runtime. No
`Explosion` instance is ever created — the burst is purely the rocket's particles.

### 6.4 End game (`modules/EndGameButtonModule.ts`)
`enter(...)` cleans up the session, stashes a `PendingPayout` `{ earned, aborted, clientOwes }`,
then (after a delay or respawn) shows the `ButtonFinishGame` popup and fires `EndGameStartEvent`
`(baseCash=EffectiveBaseCash, multiplier, lossMultiplier, claimBonus)` to drive the client
payout animation — the payload already carries the final credited amount so the animation
matches exactly. `baseCash` is the **raw** base and `claimBonus` the Perfect/Critical factor
(1 when neither rolled): the animation opens with a **phase 0** where `BaseCashText` counts up
from `baseCash` to `baseCash × claimBonus` in gold (with a `BASE CASH ×N` banner), so the
bonus is visibly applied to the base and not to the multiplier (§6.3); every later phase runs
on the boosted base. `multRebirth` was removed from the payload; the client animation no longer has a
gold rebirth phase. The client signals `EndGameFinishedEvent` when the animation ends →
server credits `Money` and hides the popup.
**Money is credited only after the client animation completes** (single source of truth).
- `enterRewardOnly(player, reward)` is the **losing-explosion** path (§6.3): no popup — it
  cleans up the session, hides the `RocketLaunch` popup, stashes `reward` in the **same
  `pendingEarned` map**, and fires `LossRewardEvent(reward)`. The client (`LossRewardBehavior`)
  re-enables the HUD, jumps a single "+reward" text into the money display, then fires the
  **shared** `EndGameFinishedEvent` on arrival → the same handler credits `reward` and the HUD
  counter reconciles with no jump. One new server→client event, and no duplicate credit logic.

**Flush — the finish screen never steals a screen the player just opened.** `UiService.Show`
calls a registered `SetBeforeShow` hook for **any** popup other than `ButtonFinishGame`; the hook
is `EndGameButtonModule.flush(player)`. Typical case: the player re-triggers the button or the
rocket during the 1 s `RELEASE_DELAY` (the prompt is already free — `cleanup` ran), which would
otherwise pop the finish screen over the fresh `ButtonMenu`. `flush` marks the entry `aborted`
(so the waiting `enter` task opens nothing) and fires `EndGamePayoutFlushEvent(earned)`:
- Client (`EndGameButtonBehavior`) calls `EndGameAnimation.cancelActiveRun()` — stops a payout
  already playing, destroys its in-flight chunks, resets the popup labels to their Studio
  baseline, clears the "Finish" flash (`InformationText.hide()`), and returns what its chunks
  have **not** banked yet. `undefined` when nothing was playing → the server's `earned` is used.
- The amount is then shown by `FloatingReward.show(amount, "fade")`: one "+amount" that jumps at
  screen centre and **fades on the spot**. No `InGameUIController.enable()`, no BGM resume — the
  new screen hid the HUD, so there is no visible counter to fly into and nothing must pop over it.
- Credit is unchanged: the text fires `EndGameFinishedEvent` when it fades. `earned <= 0` drops
  the finish screen with no text at all.
- `staleSignals` guards the tail case where a whole new run finishes inside the ~1.5 s the text
  lives: `enter` banks the superseded entry early, and the text's late signal is swallowed instead
  of crediting (and closing) the payout that replaced it.

`client/ui/FloatingReward.ts` owns the single-text visual for both endings — `"fly"` (into the
money HUD, used by `LossRewardBehavior`) and `"fade"` (in place, used by the flush). Its frames
are named `LossRewardFloatingText` so `FloatingCash` still drops them on a rebirth.
Both endings **bank on disappearance** (`MoneyDisplay.addVisual` + `EndGameFinishedEvent`).
`showAlreadyCredited(amount, ending)` is the same text **without** the banking — for a gain the
server has already credited (the daily reward, §6.25), where banking would count the money a
second time on screen and fire an end-game event unrelated to it.

### 6.5 Popups (`UI/Popup.ts`, `UI/PopupConfig.ts`, `services/UiService.ts`)
- `PopupType` enum (`shared/PopupType.ts`): `ButtonMenu`, `RocketLaunch`, `ButtonFinishGame`.
  (The `RocketLaunch` popup — formerly `ButtonInGame` — holds the live `MultiplierText`, the
  `ClaimButtonFrame/ClaimButton`, and the `ResultMultiplierText` — a live "if you claim now"
  cash-out preview (`"{n}$"`) that throttles as the multiplier climbs and freezes on claim
  (§6.3); the old `Slider`/progress-bar was removed.)
  `MultiplierText` **stays red for the whole flight**: `RocketLaunchBehavior` lerps it from
  `MULTIPLIER_COLOR_START` (light red) to `MULTIPLIER_COLOR_FULL` (deep red) over
  `MULTIPLIER_HEAT_UPDATES` server ticks (~5s). Both bounds live in code — the colour set on
  the label in Studio is *not* the ramp's start, so re-styling the GUI can't change the hue.
  The label is `TextScaled` in Studio, so the `TextSize` bump is invisible in flight; it is
  kept only because `MultiplierVisuals` hands it to the `ButtonFinishGame` popup (which is
  *not* `TextScaled`), and it is now capped at `MAX_MULTIPLIER_SIZE_INCREASE`.
- Server `PopupConfig` maps each type to a behavior class; `UiService` shows/hides by type
  and tracks one current popup per player (showing a new one hides the previous).
- `UiService.SetBeforeShow(cb)` registers one hook called just before **any** popup other than
  `ButtonFinishGame` opens. `EndGameButtonModule.init()` registers `flush` there (§6.4) — a
  callback rather than a direct import so `UiService` stays free of gameplay dependencies.
- A popup resolves `PlayerGui/InGameUI/<className>` Frame and toggles `Visible`.
- Client mirrors this with `PopupBehaviors/` + `behaviors/` that animate the frames.

### 6.6 Persistence (`PlayerDataService`, `PlayerProgressionService`)
- Both follow the same pattern: **DataStore-backed, mirrored to player Attributes** so the
  owning client can read state directly via replication.
- `PlayerDataService` → `Money`, **`ScrollTokens`** (la monnaie des quêtes, §6.26),
  **`ScrollMoneyBoost`** (0/1 — le ×1.25 argent permanent acheté en tokens, §6.27),
  **`Playtime`** (total seconds played, accumulated across
  sessions) **and the two daily-reward keys `DailyStreak` / `DailyLastClaim`** (§6.25) — all
  default 0 for existing saves, no version bump (store `PlayerData_v1`).
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
  The bar has **two display states**, swapped by `setReady(money >= cost)`:
  *filling* shows `RebirthFrame` (`RebirthImage` + `RebirthLevelText` — `"Rebirth {R}"`,
  refreshed on the `Rebirths` attribute) + `BackgroundFrame` (`MoneyNeededText`); *ready* hides both
  and shows `LevelUpText` ("Click to rebirth") plus `CurrentProgressionFrame/RebirthButton`,
  which at 100% spans the whole bar. `LevelUpText` gets a golden call-to-action animation —
  its authored `GoldGradient` sweeps `Offset` −1 → 1 on a loop while a reversing Sine tween
  pulses the label to 1.08× — both cancelled (and the size restored) when the state flips
  back. The button calls `openRebirthMenu()` from `RebirthMenuBehavior`, the same entry
  point as the HUD rebirth icon.
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
  open/close handled by `ShopBehavior`). Opening hides the persistent HUD (§6.7) — which
  includes the HUD's own `MoneyParent` money display — so `ShopBehavior` also toggles a
  **second `MoneyParent`** (a direct sibling of `ShopMenu` under `InGameUI`, hidden by
  default) in lockstep with the shop: visible while shopping, hidden on every close path.
  > `ShopBehavior` resolves it with `FindFirstChild` and warns instead of `WaitForChild`:
  > the client inits run **sequentially** in `main.client.ts`, so an infinite yield here
  > silently kills every behavior registered after the shop (rebirth menu, daily rewards,
  > HUD progression…). If the frame is missing, only the balance readout while shopping is
  > lost — re-authoring it in Studio brings it back with no code change.
  > Le miroir est un duplicata complet du `MoneyParent` du HUD, **`PlusButton` compris** :
  > `ShopMoneyBuyBehavior` branche donc les DEUX "+" sur la même ouverture (§6.15), sinon
  > celui du miroir serait un bouton mort. Là aussi la résolution est en `FindFirstChild`.
  > `MoneyText` n'a besoin de rien : `MoneyDisplay` écrit dans **tous** les labels de ce nom
  > sous `InGameUI`.
  Four buttons map to the upgrades:
  `BButtonMoney` = BaseCash +1, `BX5ButtonMoney` = BaseCash +5, `ARocketSpeed` = RocketSpeed +1,
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
    Resistance `level` (plain integer, `maxLevel` 100). Start prices **50 / 75 / 75**
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
  stat's `display` in `ShopConfig.STATS`) and the cash price (`BuyButton/TextLabel`, via
  `FormatNumberRounded` — a whole-number abbreviation with no decimals, "16K" not "15.5K"),
  greys unaffordable buttons, shows `MAX` at the Resistance cap, and fires `ShopPurchaseEvent`. The
  per-stat display: BaseCash shows the **effective** `$` gain (`floor(value * MoneyMult)`, so it
  already reflects rebirth/boosts); RocketSpeed shows the raw speed alone, e.g. `"3"` (the
  `(x6.0)` multiplier preview was removed); Resistance (frame `DSafety`,
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
- `ShopConfig` exposes the pure pricing/reward: `rebirthCost(R) = floor(20 000 × 38^R)`, with
  `REBIRTH.firstCosts` overriding the first entries (R0 = **1 000**, so the first rebirth lands
  in ~6 runs / ~2.5 min and teaches the mechanic; R1+ untouched at 760 000, 28.9 M…), and
  `rebirthMult(R) = 8^R` (geometric — no lookup table). `multGrowth` = 8 is calibrated so a
  player recovers their pre-rebirth peak income in ~3 runs (they restart with all 3 stat
  levels at 0); `costGrowth` = 38 deliberately outpaces that, so rebirth cycles lengthen
  progressively (R1 ≈ 5 min, R4 ≈ 8 min, R7 ≈ 16 min) instead of staying flat.
- **`RebirthMenuBehavior` (client)** — open/close only; starts hidden regardless of the Studio
  default (mirrors `ShopBehavior`). Exports `openRebirthMenu()` so every entry point shares one
  open path: the HUD rebirth icon and the progression bar's `RebirthButton` (§5).
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
    reset to 0. So a normal rebirth also calls **`EndGameButtonModule.cancelPending`** (drops the
    player's pending payout — including a waiting one, marked `aborted` so its `enter` task opens
    nothing — and hides the finish popup, so a late `EndGameFinishedEvent` credits nothing) and
    fires **`RebirthResetEvent`** (S→C) → client **`FloatingCash`** (`client/ui/FloatingCash.ts`)
    destroys the in-flight floating frames and bumps a generation so their arrival callbacks no-op.
    **Safe rebirth does neither** — it keeps Money, so an in-flight payout must still land.

### 6.10 Audio (`shared/AudioConfig.ts`, `client/audio/MusicController.ts`, `client/audio/UiClickSound.ts`)
- **`AudioConfig` (shared)** is the single registry of every sound asset (id + volume):
  the BGM `playlist`, the `highAltitude` ascent track, and the `sfx` (server `explosion` +
  `rocketLaunch` (looped 3D engine roar — see §6.17),
  client `buttonUpgrade` / `moneyGain` / `uiClick` / `perfectClaim` (shared by both claim flashes, §6.22); `buttonExplode` is still defined
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
    `HIGH_ALTITUDE_MUSIC_THRESHOLD` (65) studs, calls `enterHighAltitude()` **once per run** — which
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
- **Data:** two `OrderedDataStore`s — `LB_Money_v2` (value = **encoded** rank of current `Money`)
  and `LB_Playtime_v1` (value = total seconds). They are a **ranking index only**; the source of
  truth for playtime is the `Playtime` key on `PlayerDataService` (safe-save guarded). Money
  ranks **current** cash, so it drops to 0 on rebirth (see §6.6, §6.9).
- **Money rank encoding** (`encodeMoneyRank`/`decodeMoneyRank` in `LeaderboardService`):
  OrderedDataStore only accepts signed-64-bit integers (max `9.22e18 ≈ "9.22Qi"`), so raw Money
  used to freeze the board there. Instead we store a **monotonic, order-preserving** pack of the
  base-10 exponent + mantissa (`(exp + 40) * 1e15 + mantissaPart`). Sort order matches the real
  value's, `decodeMoneyRank` recovers ~15 significant digits for display (far more than
  `FormatCash` shows), and the ceiling rises to ~`1e308` (double max). `readTop` takes an optional
  `decode` (identity for playtime, `decodeMoneyRank` for money). The store was bumped `v1→v2`
  because old raw entries are incompatible with the decoder.
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

### 6.15 Developer products (`shared/MoneyProducts.ts`, `shared/LevelProducts.ts`, `shared/RebirthProducts.ts`, `shared/DailyRewardConfig.ts`, `server/services/MoneyProductService.ts`, `client/behaviors/ShopMoneyBuyBehavior.ts`, `client/behaviors/ShopItemsController.ts`)
Four families of Robux developer products, all routed through one `ProcessReceipt`:
- **Money packs** — Robux "buy money" packs sold from the **`InGameUI/ShopMoneyBuy`** popup
  (separate from the upgrade `ShopMenu`, §6.8). Nine packs, opened from the HUD's
  `MoneyParent/PlusButton/TextButton`.
- **Progression products** — 3 products sold on the upgrade `ShopMenu` **RobuxButtons** (§6.8):
  BaseCash +10 levels (on both the +1 and +5 frames), RocketSpeed +10 levels, Resistance +1 level.
- **Safe rebirth** — 1 product sold on the Rebirth menu's `SafeRebirthButton` (§6.9): a paid
  rebirth that **keeps all progression** (Money + stat levels) and only grows the permanent
  multiplier. `shared/RebirthProducts.ts` holds the id (`SAFE_REBIRTH_PRODUCT_ID`) +
  `isSafeRebirthProduct(id)` lookup, shared by the client prompt and the server grant.
- **Daily 3X claim** — 1 product sold on the DailyRewards popup's `X3ClaimButtonFrame` (§6.25):
  triples the day's reward. `shared/DailyRewardConfig.ts` holds the id (`DAILY_X3_PRODUCT_ID`)
  + `isDailyX3Product(id)`; the grant delegates to `DailyRewardService.claimPaid`.

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
  (value 1 = level 0's default, reaches 30 studs/s in 10s; value 6 = accel 18 / max 180). A scripted
  tutorial run may scale it further via `ScriptedRun.speedFactor` (the first launch flies at ×0.5 so
  the player can read what happens); outside the tutorial the factor is 1.
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
  (`CameraPosPart`, `CameraParentPart`, `ParticlesParentPart`,
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

### 6.19 Analytics (`server/services/AnalyticsService.ts`)
Official **Roblox** analytics (Creator Hub → your experience → **Analytics**). **No Studio setup**
is required — the events flow to the dashboard automatically for a published experience (first data
lands after ~24h; nothing shows for Play Solo). `AnalyticsService` is a thin, **crash-proof wrapper**
around the engine `AnalyticsService`: every log call is wrapped in `pcall` (analytics can throttle
or be disabled — it must never break gameplay), server-only, and exposes semantic one-liner helpers
so call sites stay readable. Because gameplay is server-authoritative, every event is logged from the
server at the exact point state truly changes.
- **Economy** (`cashSource` / `cashSink`, currency `"Cash"`, `Enum.AnalyticsEconomyFlowType`):
  - **Source** — gameplay payouts (`EndGameButtonModule.creditPending`, logged at the true credit
    with the resulting balance; `itemSku` `ClaimWin` / `LossConsolation`) and Robux money packs
    (`MoneyProductService`, `TxType.IAP`).
  - **Sink** — shop purchases (`ShopService`, `itemSku` = the item id) and rebirths
    (`RebirthService`, the whole balance leaves the economy → ending balance 0).
- **Onboarding funnel** (`onboardingStep`, `LogOnboardingFunnelStepEvent`) — **first-session players
  only**, gated by `PlayerProgressionService.isFirstSession` (true only when the DataStore load found
  no existing record) and de-duped per step per session: 1 Joined → 2 Launch → 3 Claim → 4 Purchase
  → 5 Rebirth. Returning players skip it entirely (a no-op), so the numbers stay meaningful.
- **Core-run funnel** (`runStep`, `LogFunnelStepEvent`, funnel `"CoreRun"`) — **repeatable**, one
  `funnelSessionId` (a GUID from `newRunId`) per run: 1 Launch → 2 Claim → 3 Banked. A loss never
  reaches step 3, so the drop-off between 2 and 3 is the loss rate.
- **Progression** (`rebirth`, `LogProgressionEvent`, path `"Rebirth"`, status `Complete`, level =
  rebirth count) — logged by both normal and safe rebirths.
- **Custom counters** (`custom`, `LogCustomEvent`, optional numeric value + one breakdown field mapped
  to `Enum.AnalyticsCustomFieldKeys.CustomField01`): `RocketLaunched`, `RunClaimed`, `RunGoHome`,
  `RunLost`, `ShopPurchase`, `RebirthDone`, `SafeRebirthDone`, `MoneyPackPurchased`,
  `LevelProductPurchased`, `GamePassPurchased`, `CommunityJoined`.
- **No new RemoteEvents** — everything is server-side (the economy is already server-authoritative),
  and no gameplay logic depends on analytics succeeding.

### 6.20 Information banners (`shared/InformationRarity.ts`, `client/ui/InformationText.ts`)
Bandeaux d'information du HUD (« Pas assez d'argent », « Finish », etc.), **empilables** et
déclinés en **4 raretés**. Purement présentation, 100 % client.
- **Studio** — `InGameUI/InformationTextCanvasGroup` n'est plus le bandeau mais le **conteneur**
  de la pile : fond transparent, `GroupTransparency = 0`, `UIListLayout` vertical
  (Top / Center, `SortOrder = LayoutOrder`). Il contient un unique template
  `InformationEntry` (CanvasGroup, `Visible = false`) :
  `InformationEntry → FrameParent` (le bandeau sombre + son `UIGradient`) `→ InformationText`
  (TextLabel + `UIStroke` + `CommonGradient` / `RareGradient` / `EpicGradient`) et
  `LegendaryText` (TextLabel + `UIStroke` + `UIGradient` + LocalScript `RainbowText`).
  Le gradient ne peut PAS être posé sur le CanvasGroup lui-même (il teinterait tout le
  groupe composité, texte compris) — d'où le `FrameParent` intermédiaire.
- **Empilement** — chaque `show()` clone le template, lui donne un `LayoutOrder` croissant
  (le nouveau bandeau apparaît **sous** le plus récent) et l'anime avec son propre fondu
  (`GroupTransparency` par entrée). Plafond `MAX_ENTRIES = 5` : le plus ancien saute.
  Après le fondu de sortie l'entrée est `Destroy()`ée ; `hide()` vide toute la pile d'un coup
  (utilisé par `EndGameAnimation` §6.4).
- **Raretés** (`STYLES` dans `InformationText.ts`) — chacune a sa **hauteur** (le texte est
  `TextScaled`, donc la hauteur = la taille du texte), sa **durée d'affichage**, son gradient et
  son son :

  | Rareté | Hauteur (fraction d'écran) | Hold | Gradient | Son |
  |---|---|---|---|---|
  | `Common` | 0.08 | 5 s | aucun (la couleur passée s'applique) | **aucun** (bandeau le plus fréquent) |
  | `Rare` | 0.09 | 5 s | `RareGradient` | `sfx.information` |
  | `Epic` | 0.10 | 5 s | `EpicGradient` | `sfx.information` |
  | `Legendary` | 0.12 | 6,5 s | TextLabel dédié `LegendaryText` + `RainbowText` | `sfx.informationLegendary` |

  Le *hold* est le temps à pleine opacité, hors fondus (+0,7 s au total) ; `holdSeconds` à
  l'appel le surcharge. **Exception :** le flash `Finish` de fin de partie **séquence**
  l'animation de paiement (§6.4 attend `FADE_IN_TIME + HOLD_TIME`), il repasse donc
  explicitement `HOLD_TIME` (0,2 s) et garde sa durée courte historique.
  Les hauteurs sont exprimées en fraction de l'**écran** et converties à la volée par rapport
  au conteneur (`entryHeightScale`), donc redimensionner le conteneur en Studio reste sans effet
  sur la taille des bandeaux. Un `CommonGradient` existe en Studio mais reste éteint (Common =
  sans gradient) : le renseigner dans `STYLES` suffit à l'allumer.
- **`RainbowText`** est un **LocalScript désactivé dans le template**, activé par le code
  uniquement sur les bandeaux `Legendary` (une boucle par bandeau affiché, détruite avec lui).
  Placeholder à retravailler (arc-en-ciel mouvant).
- **Sons** — joués par code (clones de templates persistants en `SoundService`, comme
  `UiClickSound` §6.10) depuis `AudioConfig.sfx.information` / `informationLegendary`.
- **Descente pendant un vol** — `InformationText.setInFlight(inFlight)` déplace le CONTENEUR
  (tween 0.25 s) entre sa position Studio et `IN_FLIGHT_Y` (0.24). Le HUD de vol pose son gros
  `MultiplierText` en haut-centre (0.08 → 0.21 de l'écran), pile là où la pile s'empile : les
  bandeaux passent donc dessous le temps du vol. Piloté par `RocketLaunchBehavior` — `true` au
  décollage (`startGame`), `false` sur `GameResultEvent`, le seul point de passage commun à
  toutes les fins de partie (explosion post-claim, perte, « Go Home »). La position authored
  est capturée au premier appel, donc avant tout déplacement.
- **API** — `InformationText.show(text, { rarity?, color?, holdSeconds? })`
  (`InformationTextOptions`, partagé dans `shared/InformationRarity.ts`). Le serveur passe le
  même objet d'options via `InformationTextEvent`.

### 6.21 Cash burst on claim (`client/ui/MoneyBurst.ts`, `client/audio/CashSound.ts`)

Purely client-side 2D particle burst played on `ClaimAcceptedEvent`: `PARTICLE_COUNT` (26)
`ImageLabel`s of the money bill (`rbxassetid://18209585783`) spawn on the centre of the
`InGameUI` ScreenGui, shoot outward over the full circle at `SPEED_MIN..SPEED_MAX` px/s, then
fall back down. Not a `ParticleEmitter` — the bills must render over the HUD, so it is a small
pixel simulation stepped in `RunService.RenderStepped` (a single connection, opened on the
first burst and closed once the last bill dies).

Per bill: exponential `DRAG` (fast burst → soft settle; terminal fall speed ≈ `GRAVITY / DRAG`),
`GRAVITY`, a damped random `spin`, a sine `SWAY` for the paper-in-the-air feel, a `POP_TIME`
scale-in, and a fade from `FADE_START` to `LIFETIME` (2.6 s) before `Destroy()`. All pixel
constants are authored for `REFERENCE_HEIGHT` (900 px) and rescaled by the real viewport height,
so the burst reads the same on mobile. `MoneyBurst.preload()` (called from
`RocketLaunchBehavior.init`) warms the image so the first claim of the session is not blank;
`MoneyBurst.clear()` wipes bills still in flight.

**Variante "aspiration"** — `play(origin, { gatherTo })`. Le billet explose normalement
pendant `GATHER_DELAY` (0.55 s), puis :
1. **freinage** sur `GATHER_BRAKE` (0.2 s) — le billet continue sur sa lancée en ralentissant
   jusqu'à l'arrêt, translation et rotation comprises. Sa vitesse est multipliée par
   `1 − smoothstep(t)` : elle vaut encore celle de l'explosion à l'entrée, exactement zéro à la
   sortie, **dérivée nulle aux deux bouts**. La pause est bien là, mais on y glisse. (La gravité
   ne s'applique plus pendant le freinage, sinon le billet ne s'immobiliserait jamais.) Le point
   d'arrêt réel est réécrit à chaque image et sert d'origine à la ligne droite ;
2. **vol en ligne droite** vers la cible en `GATHER_TIME` (0.75 s), easing **p²** — dérivée nulle
   en p = 0, donc le départ se fait à vitesse nulle, dans la continuité exacte du freinage — en
   rétrécissant à `GATHER_END_SCALE` et en s'effaçant sur la fin. La
   rotation rejoint `GATHER_END_ROTATION` (0 = droit) par le chemin angulaire le plus court
   (`shortestAngle`) — jamais un tour complet pour rattraper 20° : le billet cesse de
   tournoyer et arrive à plat dans le compteur.

Le mouvement est donc **C¹ d'un bout à l'autre** : aucune des trois phases n'introduit de saut
de vitesse, ni en translation ni en rotation.

Les départs sont **échelonnés** dans l'ordre d'émission (donc en vague autour du cercle) sur
`GATHER_SPREAD` (0.25 s) plus un bruit `GATHER_JITTER` (0.05 s) : aucun basculement collectif,
et une arrivée en rafale.

Chaque billet qui touche la cible joue `playBillPop()` (`AudioConfig.sfx.billPop`) : les 26
arrivées étalées font un crépitement plutôt qu'un seul son, d'où un volume propre, distinct de
`uiClick` qui partage pourtant le même asset.

`gatherTo` est une **fonction** appelée au moment du départ, pas à
l'explosion — le HUD peut très bien être masqué quand la gerbe part (c'est le cas de la
récompense journalière, §6.25) ; elle renvoie une position **écran absolue** que `MoneyBurst`
reconvertit dans le repère de son ScreenGui. Si elle renvoie `undefined` (HUD introuvable), le
billet repasse en chute + fondu normaux — jamais figé en l'air. Utilisée par la récompense
journalière : les billets finissent dans le compteur d'argent du HUD.

> Les **sons d'argent** vivent dans `client/audio/CashSound.ts` : `playCashSound`
> (`sfx.moneyGain`), `playBillPop` (`sfx.billPop`) et `preloadCashSound` qui précharge les
> deux. Un petit `makeSfx` local fabrique chacun — un template cloné à chaque lecture, donc
> pas de fetch CDN au moment du gain et des lectures qui se superposent sans se couper. Le son
> de cash est partagé par
> le claim (`RocketLaunchBehavior`), chaque dépôt du compteur (`MoneyDisplay.addVisual`) et la
> récompense journalière. C'est le même feedback "j'ai encaissé", il ne doit pas diverger.

### 6.22 Claim flashes (`client/ui/ClaimFlashText.ts`)

Purely client-side full-screen flashes, **stackable** like the `InformationText` banners
(§6.11): each call creates its own label and takes the next free line (`SLOT_SPACING` 0.15 of
screen height below `BASE_Y` 0.43, `MAX_FLASHES` 3 — the oldest is dropped past that), so two
flashes never land on top of each other. Same animation, same SFX for both:

| Call | Text | Look | When |
|---|---|---|---|
| `showPerfect()` | `PERFECT CLAIM  BASE CASH ×3` | flat red | on `PlayerKilledEvent`, i.e. **at the explosion** — `ClaimAcceptedEvent(_, perfect = true)` only sets the `perfectClaimPending` latch in `RocketLaunchBehavior` (reset at every launch) |
| `showCritical()` | `CRITICAL CLAIM  BASE CASH ×10` | **golden, shining** — a `UIGradient` (dark gold → white highlight → dark gold, `SHINE_ROTATION` 20°) whose `Offset` sweeps −1 → +1 on a looping `SHINE_TI` (1 s, linear), so a reflection keeps crossing the text | **on the claim itself**, straight from `ClaimAcceptedEvent(_, _, critical = true)`, on the same frame as the icon rain (§6.23) |

A single run can show both (critical at the claim, perfect ~a few tenths later at the blast):
the second one simply stacks under the first.

**Nothing to author in Studio**: each `TextLabel` (+ `UIStroke` + `UIScale`, + `UIGradient` for
the critical) is created in code under the `InGameUI` ScreenGui, `TextScaled` with a size in
scale so it reads the same on mobile, `ZIndex` 60 so it sits over the HUD and the cash burst.

Violent arrival, long read: it arrives at `START_SCALE` (×2.4) tilted `START_ROTATION`
(−7°) and slams to its real size in `SLAM_TI` (0.13 s, `Back/Out` ⇒ small overshoot) while the
text + stroke fade in over `APPEAR_TI` (0.06 s), holds `HOLD` (**2 s**), then fades out growing
to `OUT_SCALE` in `OUT_TI` (0.22 s) before the label is destroyed — ~2.35 s total, so it is
still on screen (already fading) when the finish popup opens `EXPLOSION_VIEW_DELAY` (1.5 s)
after the blast. No overlap: the popup's labels sit at y 0.33 and 0.80. The SFX
(`AudioConfig.sfx.perfectClaim`, shared by both flashes) fires on the same frame, from a
persistent `SoundService` template like `UiClickSound`/`InformationText`. Each flash carries
its own `alive` flag so an early removal invalidates its in-flight `task.delay`s;
`ClaimFlashText.hide()` cuts every flash instantly. Both labels build their text from
`PERFECT_CLAIM_MULTIPLIER` / `CRITICAL_CLAIM_MULTIPLIER`, so retuning a bonus updates what the
player reads.

### 6.23 Critical Claim rain (`client/ui/CriticalRain.ts`)

Small 2D icon rain (`rbxassetid://13506500866` par défaut) dropped by `CriticalRain.play()` on the same
frame as the golden flash (§6.22), from the `ClaimAcceptedEvent` handler. Same technique as the
cash burst (§6.21) — `ImageLabel`s simulated in pixels inside `RenderStepped`, no
`ParticleEmitter`, since it has to read over the HUD — but a fall instead of an explosion.

`PARTICLE_COUNT` (40) icons spawn spread across the screen width (column + noise, no clumps)
and, crucially, **staggered in height**: each starts somewhere in a `SPAWN_BAND` (1600 px) band
*above* the top edge, so they enter the frame one after another and read as rain rather than a
single volley — no timers involved. `SPAWN_BAND` is therefore also the rain's **duration** knob:
a taller band means the last icons enter the frame later. Each falls at `FALL_SPEED_MIN`…`MAX` (340–620 px/s) with a
light `GRAVITY` (300 px/s²), a random horizontal `DRIFT_MAX` drift, a slow `SPIN_MAX` spin and a
sine `SWAY` for the falling-leaf feel. Past `FADE_START_Y` (68 % of screen height) an icon
dissolves progressively and is destroyed once below the bottom edge (`MAX_LIFETIME` 9 s is only
a safety net). All pixel constants are authored for `REFERENCE_HEIGHT` (900 px) and rescaled by
the real viewport height, so it reads the same on mobile. `ZIndex` 55: over the HUD and the cash
burst, **under** the flash text (60). `CriticalRain.preload()` (called from
`RocketLaunchBehavior.init`) warms the image; `CriticalRain.clear()` wipes icons still falling.

`play(image?)` / `preload(image?)` prennent une **image optionnelle** : la même simulation
sert la pluie jouée à l'accomplissement d'une quête (§6.26), qui doit être exactement le même
effet avec une autre icône. Sans argument, c'est celle du Critical Claim.

### 6.24 Mega Rocket (`shared/MegaRocketConfig.ts`, `server/services/MegaRocketService.ts`, `client/ui/MegaRocketVisuals.ts`)

Événement global à l'échelle du serveur : toutes les `MEGA_ROCKET_INTERVAL` (**6 min**),
**tous** les joueurs reçoivent une **Mega Rocket** — une fusée arc-en-ciel, légèrement plus
grande, dont le vol paie `MEGA_ROCKET_BASE_CASH_MULT` (**×8**) sur le base cash. Une seule par
événement : elle est **consommée par le vol qui la décolle**.

- **État = un attribut joueur** (`MegaRocket`, répliqué — pas de RemoteEvent) : le serveur le
  pose, `RocketPlacer` en déduit les visuels, `ButtonInGameModule` le ×8, et le client s'en sert
  pour aligner son aperçu de gain. `hasMegaRocket(player)` (lecture pure) vit dans
  `shared/MegaRocketConfig.ts` avec toutes les constantes ; le service ne garde que l'horloge et
  `consume(player)`.
- **Au top de l'événement** (`MegaRocketService`, initialisé après `RoomService` — il lui faut
  les rooms) :
  1. l'attribut est posé sur tous les joueurs présents ;
  2. un bandeau **Legendary** (§6.20) est diffusé à tout le serveur via
     `InformationTextEvent.FireAllClients` (`MEGA_ROCKET_ANNOUNCE`) ;
  3. les fusées **encore sur leur pad** sont reposées immédiatement en version mega
     (`RocketPlacer.place`). Les rigs qui ne sont **pas** sur leur pad (vol en cours, débris
     d'explosion, retour « Go Home » pas encore reset) sont **sautés** — c'est leur replacement
     de fin de vol qui posera la mega, l'attribut étant toujours là. Le garde est
     **`RocketLauncher.isAtPad(room)`** : reposer une fusée hors du pad remplacerait le modèle
     sous les pieds du joueur **et** `clearRocketCache` effacerait le pivot du pad, ce qui
     empêcherait `reset()` de faire redescendre le rig.
- **Cycle de vie du ×8** — `startButtonGame` lit `hasMegaRocket` **une fois** (`megaRun`) et
  multiplie le `baseCash` du run ; l'attribut n'est **pas** consommé au décollage (le client lit
  la même base au même moment pour son aperçu). Il l'est en **fin de vol**, dans le helper local
  `respawnRocket()` — `consume` **puis** `RocketLauncher.reset` + `RocketPlacer.place` — donc la
  fusée qui réapparaît est normale. Les trois fins de partie (explosion post-claim, perte,
  « Go Home ») passent par ce helper. Un vol démarré **avant** le top de l'événement ne consomme
  rien (`megaRun` était faux) : le joueur retrouve sa Mega Rocket sur le pad à l'atterrissage.
  Comme tout passe par le `baseCash` local, le ×8 se propage automatiquement au payout, au lot
  de consolation, à la popup de fin (§6.4) et au forecast de debug.
- **Panneau** — `Workspace/Environment/DisplayEventPanel/SurfaceGui/MegaRocketFrame/EventText`
  (TextLabel `TextScaled` + `UIStroke`, dans un Frame de fond, créés en Studio). Le lookup
  serveur est **récursif** (`FindFirstChild("EventText", true)`) : le label peut être
  ré-emboîté en Studio sans toucher au code. Le **serveur** écrit son texte une fois par
  seconde (`megaRocketPanelText` → `"Mega Rocket in : 05:23 min"`) : c'est une instance de
  Workspace, elle se réplique donc telle quelle à tout le monde — aucun RemoteEvent, aucun
  contrôleur client à synchroniser. Au top de l'événement le panneau affiche
  `MEGA_ROCKET_PANEL_FIRED` (« MEGA ROCKET ! ») pendant 5 s ; `nextEventAt` étant **absolu**,
  cet affichage ne décale pas la cadence.
- **Visuels** — `RocketPlacer` grossit la fusée de `MEGA_ROCKET_SCALE` (**×1.15**) et pose le
  tag CollectionService `MEGA_ROCKET_TAG` sur le modèle `Rocket`. ⚠️ `Model:ScaleTo` prend une
  échelle **absolue**, pas un facteur, et les templates ne sont pas tous authored à 1
  (`RocketLvl2` est à **1.5**) : l'appel est donc `ScaleTo(GetScale() × MEGA_ROCKET_SCALE)`.
  Un `ScaleTo(1.15)` sec **rétrécissait** Lvl2 de 23 % au lieu de le grossir. L'arc-en-ciel lui-même est
  **100 % client** (`client/ui/MegaRocketVisuals.ts`) : les parts passent en `Neon` et leur
  teinte défile (`CYCLE_TIME` 2.5 s) avec un décalage proportionnel à leur hauteur dans la fusée
  (`HUE_PER_STUD`, mesuré une fois sur le pad), donc le dégradé **balaie** la fusée au lieu de la
  faire clignoter d'un bloc. Une seule connexion `RenderStepped` à 20 Hz, ouverte à la première
  fusée taguée et fermée quand il n'y en a plus (même approche que §6.21) ; un
  `DescendantAdded` récupère les parts qui arrivent après le tag (StreamingEnabled).
  Deux détails qui décident du rendu :
  - **`UnionOperation.UsePartColor`** doit être forcé à `true` : une union garde sinon les
    couleurs des formes qui la composent et **ignore** son `Color`. Les coques de
    `RocketLvl1/2/3` sont des unions — sans ça elles restaient grises au milieu de
    l'arc-en-ciel. (Les templates n'ont ni `SurfaceAppearance`, ni `TextureID`, ni `Decal`, et
    leurs `SpecialMesh` ont un `VertexColor` neutre : à part les unions, `Color` s'applique
    partout.) Les parts totalement transparentes sont écartées de la boucle — `RocketLvl4/5`
    dépassent les 120 parts.
  - **`NEON_VALUE`** (0.7) — le Neon brille proportionnellement à la luminosité de sa couleur.
    À 1 la fusée devient un bloc de lumière blanchi par le bloom et perd ses arêtes ; c'est le
    bouton pour doser le glow.

  Le **fond du panneau** (`MegaRocketFrame`, tagué `MEGA_ROCKET_PANEL_TAG` **en Studio** — le
  tag évite un chemin en dur et gère le streaming in/out du panneau) porte le même arc-en-ciel
  mais en **dégradé qui DÉFILE**, pas en aplat : un `UIGradient` dont la `ColorSequence` est
  reconstruite à chaque frame (`rainbowSequence(phase)`, `PANEL_STOPS` = 16 points, max Roblox
  20). Un spectre complet est étalé sur la largeur, teintes **décroissantes** de gauche à
  droite, `PANEL_CYCLE_TIME` (1.5 s) par tour — c'est le défilement qui fait l'effet, un aplat
  qui change de teinte ne rend pas la même chose. Deux pièges :
  - le `UIGradient` **multiplie** la couleur de fond : `BackgroundColor3` doit rester **blanc**,
    sinon les teintes sortent teintées ;
  - `UIGradient.Offset` ne **boucle pas** (les keypoints d'extrémité s'étirent), d'où la
    reconstruction de la `ColorSequence` plutôt qu'un décalage d'offset.

  `PANEL_VALUE` (1) est plus lumineux que `NEON_VALUE` — c'est une GuiObject, pas du Neon, il
  n'y a pas de bloom à contenir (le `SurfaceGui` est repassé à `Brightness = 1` : à 2 les
  couleurs se lavaient). Le dégradé est créé par le client s'il manque, donc le panneau survit à
  une réédition du Frame en Studio. Contrairement aux fusées le panneau s'anime **en
  permanence** : la boucle `RenderStepped` s'ouvre dès qu'il y a quelque chose à animer
  (panneau **ou** fusée) et ne se ferme que quand il n'y a plus rien.
- **Test** — `CheatConfig.megaRocketInterval` (normalement `undefined`) raccourcit l'intervalle
  pour voir l'événement en quelques secondes. La touche **G** (`client/MegaRocketCheat.ts` →
  `MegaRocketCheatEvent` → `MegaRocketService`) ramène le compte à rebours courant à
  `megaRocketCheatDelay` (**3 s**) à la demande, sans toucher à la cadence : l'événement
  d'après repart sur l'intervalle normal. Le serveur ne **branche même pas** l'event quand
  `megaRocketCheatKey` est faux. **MUST be `undefined` / `false` before publishing.**

### 6.25 Daily reward (`shared/DailyRewardConfig.ts`, `server/services/DailyRewardService.ts`, `client/behaviors/DailyRewardsBehavior.ts`, `client/ui/DailyRewardsAnimation.ts`)

Revenir jouer chaque jour paie **`EffectiveBaseCash × N`**, où *N* est le nombre de jours
**consécutifs** (jour 1 → ×1, jour 2 → ×2, …). Le produit Robux **3X Claim** triple ce total.

- **État persistant** — deux clés numériques de `PlayerDataService` (§6.6, mêmes store et
  mécanique que `Playtime`, aucune migration) : `DailyStreak` (jours consécutifs déjà
  réclamés) et `DailyLastClaim` (index du jour **UTC** du dernier claim, 0 = jamais).
  La frontière de jour est `floor(os.time()/86400)` — une limite globale fixe, insensible au
  fuseau du joueur.
- **État publié** — le serveur en dérive trois attributs répliqués que le client lit
  directement (aucun aller-retour pour afficher le popup) : `DailyMultiplier` (le multi qu'un
  claim appliquerait maintenant), `DailyClaimed` (récompense du jour déjà prise) et
  `DailyAutoOpen` (le popup doit s'ouvrir seul).
- **Streak** : claim d'hier → +1 ; sinon retour à 1. Le streak n'est **commit qu'au claim**,
  jamais à la connexion — se connecter sans réclamer ne casse ni ne prolonge la série.
- **Multiplicateur non plafonné** (jour 100 = ×100). `dailyMultiplier(streak)`
  (`shared/DailyRewardConfig.ts`) est le **seul** endroit qui transforme le streak en nombre :
  y mettre un `math.min` suffit à aplatir le haut de la courbe, rien d'autre ne lit le streak brut.
- **Auto-ouverture** (`DailyAutoOpen`, un attribut et **pas** un RemoteEvent : le serveur décide
  pendant que le client charge encore, un event tiré serait perdu). Le critère est **le tutorial
  en cours**, pas l'ancienneté du compte :
  - **tutorial actif** (`TutorialService.isActive`) → le popup est **reporté au premier rebirth
    fait APRÈS la fin du tutorial** (`RebirthService` appelle `DailyRewardService.onRebirth` ;
    un tutorial encore en cours maintient le report). Couvre les trois cas d'un coup : joueur
    tout neuf, tutorial repris d'une session précédente, et le **cheat `forceTutorial`** — le
    daily ne doit jamais atterrir par-dessus l'onboarding, quelle qu'en soit la raison ;
  - **sinon**, à la connexion si la récompense du jour est en attente.

  Le popup ne s'ouvre donc **que** dans deux cas : (1) au lancement, récompense non réclamée ;
  (2) au premier rebirth d'un joueur qui était en tutorial, récompense non réclamée. Rebirther
  avec la récompense du jour déjà prise n'affiche **rien** — il n'y a rien à donner.
  Une ouverture **automatique** ne vole jamais l'écran : le client attend d'être revenu à un
  écran neutre — aucun de `RebirthMenu` / `ShopMenu` / `ShopMoneyBuy` ouvert **et le HUD de
  nouveau visible** — puis laisse passer `AUTO_OPEN_AFTER_MENU_DELAY` (1.5 s). C'est le cas du
  premier rebirth : le popup est demandé alors que le menu Rebirth est encore affiché sur son
  écran de résultat et que le HUD est masqué.
  > `DailyAutoOpen` est un **compteur**, pas un booléen. Le client ouvre quand la valeur dépasse
  > celle qu'il a déjà traitée. Un booléen ne sait pas dire "rouvre" (true → true ne notifie
  > personne) et obligeait à un latch côté client. **Ne pas** réintroduire une réouverture
  > pilotée par les autres attributs (`EffectiveBaseCash` & co) : ils bougent à chaque rebirth
  > et à la résolution asynchrone des boosts au join, ce qui rouvrait le popup à chaque rebirth
  > et juste après le tutorial.
  `waitForData` attend l'attribut `TutorialStep` en plus des clés de streak : `isActive()`
  répondrait "false" pendant le chargement du tutorial, et le popup courserait précisément le
  tutorial qu'il doit éviter. Le client ouvre **une fois par session** (lecture au démarrage +
  `GetAttributeChangedSignal`).
- **Cohabitation avec le tutorial** — filet de sécurité, maintenant que la règle ci-dessus
  empêche normalement les deux de se croiser : `TutorialUI.setSuppressed` masque tout le
  ScreenGui du tutorial (dim + bandeau + flèches) le temps du popup, et `TutorialGate.lockGui`
  épargne les descendants de `DailyRewards` — même exception que le bouton Skip. Les deux vont
  **ensemble** : masquer le dim sans lever le lock donnerait un popup visible aux boutons morts.
- **Feedback de gain** : à la confirmation (`DailyRewardGrantedEvent`) le popup se referme,
  le **son de cash** est joué et **la gerbe de billets du claim** (§6.21) part du centre de
  l'écran — mais en mode *aspiration* : les billets convergent vers le centre du compteur
  d'argent du HUD (`InGameUIController.getMoneyParent()`) au lieu de retomber, et **tôt**
  (`GATHER_DELAY` 0.3 s). Le HUD est masqué pendant que le popup est ouvert, d'où la cible
  résolue tardivement (§6.21). S'y ajoute le **"+montant" flottant** de la récompense de
  consolation (§6.4), via `FloatingReward.showAlreadyCredited` — la variante sans crédit,
  puisque le serveur a déjà encaissé.
- **Claim** : `DailyRewardClaimEvent` → le serveur re-dérive streak + jour (il ne fait jamais
  confiance au client), commit, crédite `Money`, log analytics (`cashSource` faucet +
  compteur `DailyRewardClaimed`), puis `DailyRewardGrantedEvent`. Le ×3 passe par
  `ProcessReceipt` (§6.15) → `claimPaid` : si la récompense a déjà été prise (achat en course
  avec le claim gratuit, ou second achat), le ×3 est **quand même** payé sur le multi du jour
  plutôt que d'avaler un achat Robux.
- **Cheat** (§9) — `CheatConfig.dailyRewardCheatKey` + `ClientCheatConfig.dailyRewardKey` :
  le popup s'ouvre **à la connexion** même si la récompense est déjà prise (la règle du
  tutorial reste prioritaire). L'exemption s'arrête là : `onRebirth` teste `hasClaimedToday`
  sans dérogation, cheat compris, et la touche **P** appelle `devAdvanceDay` — le dernier claim
  recule d'une journée, ce qui réarme la récompense, fait monter la streak au prochain claim
  et rouvre le popup (via le compteur `DailyAutoOpen`, comme n'importe quelle autre demande
  d'ouverture — le cheat n'a pas de chemin à lui). Deux P sans claim entre les deux cassent la
  série, exactement comme deux vraies journées manquées : c'est aussi comme ça qu'on teste le
  compteur de jours qui repart de 0.
- **Popup** (`InGameUI/DailyRewards`) — menu 100 % client comme `ShopMenu`/`RebirthMenu`,
  **pas** un `PopupType` (§6.5, réservé au flow gameplay du bouton). Ouvert par
  `HUD/ButtonsFrame/DailyRewardsFrame/ImageButton` ou par `DailyAutoOpen`, fermé par
  `Header/CloseButtonFrame/CloseButton`. L'ouverture masque le HUD (`InGameUIController.disable`)
  et referme les autres menus (`RebirthMenu`/`ShopMenu`/`ShopMoneyBuy`) — l'auto-ouverture au
  premier rebirth arrive pendant que le menu Rebirth est encore affiché. Déjà réclamé →
  les deux boutons sont grisés + non-interactifs et le label Claim devient `Claimed`.
- **Animation d'ouverture** (`DailyRewardsAnimation`, présentation pure) :
  1. **cascade** — chaque élément part 24 px au-dessus et transparent, puis glisse en place,
     décalé de 0.04 s de haut en bas (~0.4 s au total). L'ordre est **recalculé depuis la
     position Y réelle** (`sortKey`), donc réarranger le popup dans Studio réordonne
     l'animation toute seule ;
  2. `BaseCashValue` est écrit direct, sans animation ;
  3. le **total** compte de 0 à `base × multi` (0.5 s) ;
  4. **en dernier**, après un temps mort volontairement long (`MULT_GAP` 0.45 s — c'est le
     morceau de bravoure du popup), le **compteur de jours** monte de **N−1 → N** pendant que
     le label grossit (`UIScale` ×1.35), flashe en or et joue le **son de cash**, avant de
     revenir à sa taille et sa couleur d'origine. Le N−1 est ce qui fait qu'un premier jour —
     ou une série qu'on vient de perdre — se voit compter **0 → 1** au lieu d'afficher son
     résultat d'emblée.
  Tout ce que la séquence touche est **capturé au premier passage** puis restauré par `stop()`
  (même discipline que `TutorialGate`) : aucune valeur "par défaut" réécrite en dur. Un
  compteur `generation` invalide une séquence abandonnée, sinon les tweens d'une ouverture
  précédente continueraient d'écrire dans les labels.
  Si `EffectiveBaseCash` bouge pendant la révélation — ce qui arrive vraiment : `BoostService`
  résout groupe + game-passes de façon asynchrone, souvent une seconde après le join — la
  séquence est **relancée** sur les nouvelles valeurs plutôt que les labels réécrits, sinon le
  compteur viserait encore l'ancien total.

### 6.26 Quêtes & ScrollToken (`shared/QuestConfig.ts`, `server/services/QuestService.ts`, `client/behaviors/QuestsBehavior.ts`)

**18 quêtes = 3 métriques × 6 difficultés.** Les trois quêtes d'une difficulté sont les
mêmes que celles de la difficulté suivante, seule la VALEUR de l'objectif change. Chaque
accomplissement paie des **ScrollToken**, la seconde monnaie.

| Quête | Métrique | Alimentée par | Easy → ??? |
|-------|----------|---------------|------------|
| Launch N rockets | `RocketsLaunched` | `ButtonInGameModule`, au décollage (une perte compte) | 5 · 25 · 75 · 250 · 750 · 2 500 |
| Buy N upgrades | `UpgradesBought` | `ShopService`, après un achat validé (NIVEAUX achetés) | 3 · 20 · 60 · 200 · 600 · 2 000 |
| Obtain Nx multiplier in total | `MultiplierTotal` | `ButtonInGameModule`, au claim (`+= claimedMultiplier`) | 10 · 100 · 1 000 · 10 000 · 100 000 · 1 000 000 |

Récompenses (Easy → ???) : 50/60/70 · 150/250/375 · 1K/1.25K/1.57K · 5K/7.5K/8K ·
25K/30K/35K · 100K/125K/135K. **Tout se retouche dans `shared/QuestConfig.ts`** (table
`TUNING`, un bloc par difficulté) — c'est le seul fichier à éditer pour rééquilibrer.

**Rampe.** Décollages et améliorations montent d'environ **×3 par difficulté** : à ~2.5
décollages/min et ~2 achats/min ça donne ~2 min / 10 min / 30 min / 1h40 / 5h / 16h par
palier. Combiné au cooldown de 5 min, les paliers bas se re-terminent en boucle pendant que
les hauts avancent en arrière-plan — c'est ce flux constant qui fait vivre la monnaie. Le
total de multiplicateur, lui, garde une rampe ×10 : il **s'auto-accélère** (un vol vaut ×1.4
au niveau 0 mais ×30 en rebirths profonds), donc ses paliers se rapprochent tout seuls à
mesure que le joueur progresse.

- **`MultiplierTotal` cumule le multiplicateur VERROUILLÉ**, pas le gain : Perfect Claim
  (×3) et Critical Claim (×10) multiplient le *base cash* (§6.3), donc ils ne gonflent pas
  le compteur. Une explosion avant claim n'ajoute rien. Le total est fractionnaire côté
  serveur (×1.0786…), arrondi à l'affichage seulement.
- **Boucle de vie d'une quête** : disponible (`TimeLeftText` = "Enable") → objectif atteint
  → récompense versée immédiatement + `QUEST_RESET_SECONDS` (**5 min**) de cooldown pendant
  lesquelles la barre reste pleine et le libellé affiche `Reset in : 4m 32s` → la
  progression retombe à 0 et la quête redevient disponible. **Une quête en cooldown
  n'enregistre AUCUNE progression** ; les autres difficultés de la même métrique, elles,
  continuent d'avancer.
- **Persistance** — store dédié `QuestData_v1` (même patron que `PlayerProgressionService` :
  garde `loadedPlayers`, save sur `PlayerRemoving` + `BindToClose` en parallèle). Le
  cooldown est stocké en **`os.time()` absolu** pour qu'il continue de s'écouler hors ligne :
  un cooldown expiré pendant la déconnexion est rechargé comme un reset déjà fait. Les
  ScrollToken, eux, vivent dans `PlayerDataService` (clé `ScrollTokens`, §6.6) — exactement
  le même chemin que `Money`.
- **Réplication : zéro RemoteEvent.** Le serveur publie deux attributs par quête —
  `Q_<id>` (progression) et `QR_<id>` (instant de reset, `0` = disponible). `QR_` est
  exprimé en **`Workspace:GetServerTimeNow()`** et non en `os.time()` : c'est la seule
  horloge réellement partagée client/serveur, donc le compte à rebours ne dépend pas de
  l'heure de la machine du joueur. La conversion os.time → temps serveur se fait au moment
  de la publication (`publish`).
- **Célébration** (`QuestCompletedEvent`, S→C, sans argument) — le seul RemoteEvent du
  système, et il ne transporte **rien** : la récompense est déjà versée et l'état déjà publié
  par les attributs, c'est un pur signal de présentation. Le client flashe le bandeau **Epic**
  "Quest finish" (§6.20) et lâche la **pluie d'icônes** du Critical Claim (§6.23) avec
  l'icône de parchemin `rbxassetid://17368118782`. Un event plutôt qu'une détection de
  transition sur `QR_<id>` côté client : au join les attributs arrivent par réplication, et une
  quête rechargée EN COOLDOWN déclencherait une fausse pluie.
- **Un seul point d'entrée de progression** : `QuestService.report(player, metric, amount)`.
  Il alimente les 6 difficultés de la métrique d'un coup et saute celles en cooldown. Une
  boucle 1 s (`tickCooldowns`) réarme les quêtes dont le cooldown est échu.
- **UI** (`QuestsBehavior`, client) — popup `InGameUI/QuestsPanel`, ouverte par
  `HUD/ButtonsFrame/QuestsFrame/ImageButton`, fermée par `Header/CloseButtonFrame/CloseButton` ;
  l'ouverture masque le HUD (`InGameUIController.disable`). Ce n'est **pas** un `PopupType`
  (§6.5, réservé au flow gameplay du bouton). Le header affiche le solde
  (`Header/ScrollTokenCount/ScrollCountText`, rendu par `ScrollTokenDisplay`). Chaque ligne est
  une Frame de `Body/ScrollingFrame` **nommée dans `QuestConfig`** (`B*` easy, `C*` mid,
  `D*` hard, `E*` insane, `F*` impossible, `H*` ???) contenant `QuestTitletext`,
  `TimeLeftText`, `ProgressionFrame/CurrentProgressionFrame` (barre, taille X en scale 0..1,
  masquée sous 1.3 % comme la barre de rebirth), `ProgressionFrame/TextLabel` ("55 / 100") et
  `Rewardtext`. Les lignes sont résolues en `FindFirstChild` (jamais `WaitForChild`) : une
  Frame manquante coûte une ligne, pas le blocage de tous les init clients suivants. Le
  repaint est piloté par les attributs (et n'a lieu que popup ouvert) ; seul le compte à
  rebours tourne sur un Heartbeat throttlé à 1 s, uniquement tant que le popup est affiché
  **et que l'onglet quêtes est celui à l'écran**.
- **Deux onglets, deux bodies exclusifs** (`QuestsPanel/ButtonsFrame`) :
  `QuestsFrame/TextButton` → `QuestsBody` (les quêtes), `ShopFrame/TextButton` →
  `BuyRewardBody` (la boutique, §6.27). Le panneau s'ouvre **toujours** sur les quêtes, quel
  que soit l'onglet quitté la fois d'avant — c'est ce que promet le bouton du HUD.
- **Cascade d'affichage** (`client/ui/QuestsBodyAnimation.ts`) — rejouée à chaque affichage
  d'un body, ouverture **et** changement d'onglet, pour qu'une bascule se lise comme un
  changement d'écran. Les éléments se révèlent l'un après l'autre en **fondu**
  (`FADE_DURATION` 0.22 s, `STAGGER` 0.035 s), pilotés par une seule boucle `RenderStepped`
  plutôt que par ~180 tweens. Fondu et pas glissement/échelle : les deux bodies sont sous un
  layout (`UIListLayout` / `UIGridLayout`) qui possède position **et** taille de ses enfants,
  donc toute animation de géométrie ferait re-couler la liste à chaque frame ; la transparence
  n'a aucun effet sur le layout. Les opacités d'origine sont capturées au premier passage puis
  restaurées (même discipline que `DailyRewardsAnimation`), et l'opacité d'origine sert de
  **plancher** — un élément authoré à 0.5 ne devient jamais plus opaque que 0.5. L'ordre suivi
  est l'ordre **alphabétique**, qui est exactement celui des deux layouts (`SortOrder.Name`).

### 6.27 Boutique ScrollToken (`shared/ScrollShopConfig.ts`, `server/services/ScrollShopService.ts`, `client/behaviors/ScrollShopController.ts`)

Le **puits** de la monnaie des quêtes : 6 achats payés en ScrollToken, dans le second onglet
du panneau (`QuestsPanel/BuyRewardBody`, §6.26). Aucun achat n'invente de mécanique — chacun
appelle un système existant.

| Objet | Frame Studio | Prix | Effet |
|-------|--------------|------|-------|
| Skip rebirth | `ASafeRebirth` | 350K | `PlayerProgressionService.safeRebirth` — +1 rebirth, niveaux ET argent conservés (§6.9) |
| 1.25x Money | `BMoneyMultiplier` | 250K | **Une seule fois**, permanent : `ScrollMoneyBoost` = 1 → +0.25 dans le facteur de boosts (§6.6) ; la carte affiche alors `CLAIM` |
| Mega rocket | `CMegaRocket` | 50K | `MegaRocketService.fireNow` — l'événement part tout de suite **pour tout le serveur** (§6.24) |
| Rocket speed | `DRocketSpeed` | 15K | +1 niveau `RocketSpeed` |
| Base cash | `ERocketBaseCash` | 20K | +1 niveau `BaseCash` |
| Resistance | `FRocketResistance` | 25K | +1 niveau `Resistance` |

- **Le prix vient de la config, jamais de Studio.** `ScrollShopController` réécrit
  `{Element}/BuyButtonFrame/DisplayElementFrame/TextLabel` au démarrage depuis
  `SCROLL_SHOP_ITEMS` : changer un prix dans `shared/ScrollShopConfig.ts` le change à l'écran
  **et** au débit, sans retoucher la GUI.
- **Achat unique = un ATTRIBUT, pas un booléen de config.** Un objet non rachetable déclare
  `ownedAttribute` (ici `ScrollMoneyBoost`, persisté par `PlayerDataService` donc répliqué).
  Le serveur s'en sert pour refuser le second achat, le client pour afficher
  **`CLAIM`** à la place du prix et masquer l'icône de token à côté (`ScrollTokenImage`) —
  « CLAIM » n'est pas un prix. L'affichage suit l'attribut (rendu au démarrage **et** sur
  `GetAttributeChangedSignal`), donc il est juste dès la connexion comme juste à l'instant de
  l'achat, sans aller-retour. Le clic est aussi neutralisé côté client une fois l'objet
  acquis : inutile d'envoyer au serveur un achat qu'il refusera et de faire clignoter un
  bandeau. La garde serveur reste, elle, la seule qui compte.
- **Achat immédiat, autorité serveur.** Le clic envoie `ScrollShopPurchaseEvent(itemId)` et
  rien d'autre : le client ne pré-valide rien (il ne connaît ni le solde exact ni les
  plafonds). Le serveur revalide solde / unicité / plafond de stat, **applique l'effet AVANT
  de débiter** — un refus tardif (stat au max) ne doit jamais coûter de tokens — puis répond
  `ScrollShopPurchasedEvent(itemId, price)`. Un refus part en bandeau rouge
  (`InformationTextEvent`). Un anti-double-clic de 0.4 s côté client n'est qu'un confort ;
  la vraie garde est le solde revalidé.
- **Retour visuel** — `ScrollTokenDisplay.spend(price)` : le compteur du header **défile**
  vers son nouveau solde (proxy `NumberValue` tweené, comme `MoneyDisplay`), prend une claque
  d'échelle, et un « -350K » monte et s'efface au-dessus. Le label volant est un **clone du
  compteur** : il hérite police, taille et contour, donc il reste juste si le style bouge en
  Studio. Il est parenté au **ScreenGui**, pas au compteur : le `UIListLayout` du compteur le
  rangerait dans sa liste et décalerait l'icône. Puis le bandeau propre à l'objet
  (`successText`). Le Mega Rocket n'en a pas : il diffuse déjà son bandeau **Legendary** à
  tout le serveur (« *X* triggered the MEGA ROCKET »), en dire plus ferait doublon.
- **Le ×1.25 est ADDITIF** (`shared/ShopConfig.moneyMult`), comme la communauté et les
  game-passes : il ajoute +0.25 au facteur de boosts, lui-même multiplié par `MultRebirth`.
  Multiplié par-dessus, il resterait un vrai +25 % ; additionné, il ne peut pas écraser les
  boosts vendus en Robux. Persisté en 0/1 par `PlayerDataService` (`ScrollMoneyBoost`), donc
  déjà répliqué — `deriveValues` le lit directement.
- **`MegaRocketService.fireNow(announce)`** déclenche l'événement **hors horloge** et
  **réarme la cadence normale à partir de maintenant** : sans ça, un achat juste avant
  l'échéance donnerait deux Mega Rockets à quelques secondes d'intervalle. Un `panelHoldUntil`
  empêche la boucle du panneau d'effacer « MEGA ROCKET ! » la seconde suivante.

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
| `ClaimAcceptedEvent` | S→C | Confirms a claim: authoritative locked multiplier (raw) + `perfect` / `critical` flags + `claimedBaseCash` (Perfect ×3 / Critical ×10 folded into the BASE CASH, §6.3/§6.22) |
| `ButtonExplodedEvent` | S→C | Explosion roll hit without a claim — client closes the run (music + bloom) |
| `PlayerKilledEvent` | S→C | Loss — rocket exploded; client lingers the camera on it then restores (no death anymore) |
| `MultiplierUpdateEvent` | S→C | New current multiplier (client lerps `MultiplierText` continuously to it) |
| `RiskUpdateEvent` | S→C | Current risk value |
| `GameResultEvent` | S→C | (exploded, earned, multiplier) — re-enable HUD |
| `EndGameStartEvent` | S→C | Start payout animation (baseCash=EffectiveBaseCash **raw**, mult, lossMult, claimBonus) — the popup grows the base by `claimBonus` before applying the multiplier (§6.4) |
| `EndGameFinishedEvent` | C→S | Animation (or floating text) done → server credits money, hides popup |
| `EndGamePayoutFlushEvent` | S→C | Another popup opened → drop the finish screen; show the leftover as one fading "+amount" (§6.4) |
| `InformationTextEvent` | S→C | Show an info banner in the HUD (args: `text`, `InformationTextOptions` — rarity/color/hold, §6.20) |
| `ShopPurchaseEvent` | C→S | Player clicked a cash buy button (arg: `ShopItemId`) |
| `RebirthEvent` | C→S | Player clicked Rebirth (no args) — server validates + resets |
| `DailyRewardClaimEvent` | C→S | Player clicked the free daily Claim (no args) — server re-derives streak + day (§6.25) |
| `DailyRewardGrantedEvent` | S→C | Daily reward credited: `amount`, `multiplier` (streak), `bonusMultiplier` (3 on the Robux ×3, else 1) |
| `QuestCompletedEvent` | S→C | Quest finished (no args) — presentation only: Epic banner "Quest finish" + icon rain (§6.26) |
| `ScrollShopPurchaseEvent` | C→S | Intention d'achat en ScrollToken: `itemId`. Prix / solde / unicité revalidés serveur (§6.27) |
| `ScrollShopPurchasedEvent` | S→C | Achat confirmé: `itemId`, `price` — tokens déjà débités, effet déjà appliqué (§6.27) |
| `QuestCheatEvent` | C→S | Cheat dev (touche U): termine une quête + crédite `questCheatTokens` (§9) |
| `CommunityJoinedEvent` | C→S | Native join card returned Joined/AlreadyMember — server re-checks (GetGroupsAsync) + grants ×2 |
| `DailyRewardCheatEvent` | C→S | **Cheat dev only** (touche P) — avance la récompense journalière d'un jour. Le serveur ne l'écoute que si `CheatConfig.dailyRewardCheatKey` (§6.25/§9) |
| `MegaRocketCheatEvent` | C→S | **Cheat dev only** (touche G) — ramène le compte à rebours Mega Rocket à 3 s. Le serveur ne l'écoute que si `CheatConfig.megaRocketCheatKey` (§6.24/§9) |

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
| `MULTIPLIER_TICK_RATE` | `shared/RocketGameConfig.ts` | 0.25s | Multiplier tick interval |
| `STARTING_MULTIPLIER` | `shared/RocketGameConfig.ts` | 1 | Base payout multiplier (start) |
| `MULTIPLIER_PER_STUD` | `shared/RocketGameConfig.ts` | 0.0061 | Multiplier gained per stud the rocket climbs (velocity-driven) |
| `ROCKET_ACCEL` | `shared/RocketGameConfig.ts` | 3 | Rocket acceleration per RocketSpeed unit (studs/s²), ×stat value |
| `ROCKET_MAX_SPEED` | `shared/RocketGameConfig.ts` | 30 | Rocket top speed per RocketSpeed unit (studs/s), ×stat value |
| `STEER_ROT_SPEED_GROUND` | `shared/RocketGameConfig.ts` | rad(4)/s | Roll rate at the pad — extremely weak |
| `STEER_ROT_SPEED_SPACE` | `shared/RocketGameConfig.ts` | rad(30)/s | Roll rate in space — responsive |
| `STEER_SPACE_HEIGHT` | `shared/RocketGameConfig.ts` | 50 | Studs above pad where roll authority reaches full |
| `EXPLOSION_VIEW_DELAY` | `shared/RocketGameConfig.ts` | 1.5s | Camera lingers on the exploding rocket before restoring |
| `PERFECT_CLAIM_MULTIPLIER` | `shared/RocketGameConfig.ts` | 3 | Base cash factor on a Perfect Claim — multiplies `claimedBaseCash`, not the multiplier (§6.3) |
| `PERFECT_CLAIM_WINDOW` | `shared/RocketGameConfig.ts` | 0.5s | Perfect Claim window on a flight ≤ reference time |
| `PERFECT_CLAIM_REFERENCE_TIME` | `shared/RocketGameConfig.ts` | 7s | Above this flight length the window widens proportionally |
| `PERFECT_CLAIM_MAX_WINDOW` | `shared/RocketGameConfig.ts` | 1.5s | Hard cap on the widened window |
| `CRITICAL_CLAIM_CHANCE` | `shared/RocketGameConfig.ts` | 0.05 | Chance for any claim to roll a Critical Claim (§6.3) |
| `CRITICAL_CLAIM_MULTIPLIER` | `shared/RocketGameConfig.ts` | 10 | Base cash factor on a Critical Claim — multiplies with the ×3 (§6.3) |
| `FLIGHT_TIME_MEAN` | `ButtonInGameModule.ts` | 7s | Average flight length at Resistance 0 (§6.3) |
| `FLIGHT_TIME_SIGMA` | `ButtonInGameModule.ts` | 0.35 | Width of the bell (multiplicative) — ↑ = extremes more reachable, mean unchanged |
| `FLIGHT_TIME_MIN` / `_MAX` | `ButtonInGameModule.ts` | 0.1s / 60s | Safety clamps on the draw |
| `TICK_RATE` | `ButtonInGameModule.ts` | 0.5s | Risk-loop interval |
| `RESISTANCE_MAX_REDUCTION` | `shared/ResistanceCurve.ts` | 0.45 | Risk floor at Resistance 100 (×0.55) — secondary lever |
| `RESISTANCE_REDUCTION_CURVE` | `shared/ResistanceCurve.ts` | 1.2 | ↑ = more back-loaded `riskScale` reduction (power of `n`) |
| `RESISTANCE_SAFE_WINDOW_BURST` | `shared/ResistanceCurve.ts` | 5s | Front-loaded part of `safeWindow` — ~+0.5s/level at the start, spent by ~L20 |
| `RESISTANCE_SAFE_WINDOW_CURVE` | `shared/ResistanceCurve.ts` | 9 | ↑ = burst concentrated harder on the first levels (§6.3) |
| `RESISTANCE_SAFE_WINDOW_LINEAR` | `shared/ResistanceCurve.ts` | 9s | Flat +0.09s/level, L1→L100 — keeps late levels worth buying |
| `RESISTANCE_MAX_SAFE_WINDOW` | `shared/ResistanceCurve.ts` | 14s | Derived (burst + linear) — guaranteed head start at Resistance 100 |
| `LOOSE_WIN_MULTIPLIER` | `ButtonInGameModule.ts` | 0.3 | Payout factor on loss (rocket explodes) |
| `EXPLOSION_BLAST_RADIUS` | `ButtonInGameModule.ts` | 12 | Scoped blast/fling |
| Default `BaseCash` / `RocketSpeed` | `PlayerProgressionService.ts` | 100 / 1 | New-player progression (level 0) |
| Value curves (BaseCash / RocketSpeed) | `shared/ShopBalance.ts` | ×1.2 per level / +1 per level | BaseCash exponential; RocketSpeed integer linear |
| Price growth (per stat) | `shared/ShopBalance.ts` | ×1.8 / ×1.7 / ×1.35 per level | BaseCash / RocketSpeed / Resistance — each stat has its own `priceGrowth`, no shared constant |
| Shop start prices | `shared/ShopBalance.ts` | 50 / 75 / 75 | BaseCash / RocketSpeed / Resistance lvl 1 |
| `Resistance` cap (shop) | `shared/ShopBalance.ts` | 100 lvls | Max resistance level (risk curve in §6.3) |
| `RESISTANCE_PASS` | `shared/ShopBalance.ts` | +20 lvls | Bonus resistance levels from the resistance game-pass (id 0 = inert) |
| `COMMUNITY` | `shared/ShopBalance.ts` | group 963505568, ×2 | Group membership ⇒ +1 bonus to the boosts factor, which is then MULTIPLIED by `MultRebirth` to form `MoneyMult` |
| `MONEY_TIERS` | `shared/ShopBalance.ts` | ×2…×1024, highest owned wins | Game-pass money-tier multipliers (ids configured; sold via shop upsell + HUD MultiplierBuyButton) |
| Rebirth base cost | `shared/ShopBalance.ts` | 20 000 | Base of the cost curve (used from R1 on) |
| Rebirth first costs | `shared/ShopBalance.ts` | `[1 000]` | Imposed cost of the 1st rebirth (~6 runs / ~2.5 min) — overrides the curve at R0 only |
| Rebirth cost growth | `shared/ShopBalance.ts` | ×38 / rebirth | `rebirthCost(R)=floor(20 000×38^R)` outside `firstCosts` |
| Rebirth mult growth | `shared/ShopBalance.ts` | ×8 / rebirth | `rebirthMult(R)=8^R` (geometric, no lookup table) — the `MultRebirth` factor that MULTIPLIES the additive boosts factor in `MoneyMult` (see §6.6) |
| `dailyMultiplier(streak)` | `shared/DailyRewardConfig.ts` | ×N at day N, **uncapped** | Daily reward multiplier — the only place the streak becomes a number, clamp here to flatten the top end (§6.25) |
| `DAILY_X3_MULTIPLIER` | `shared/DailyRewardConfig.ts` | 3 | Factor of the Robux "3X Claim" daily product (id `3709014909`) |
| `MEGA_ROCKET_INTERVAL` | `shared/MegaRocketConfig.ts` | 360s | Délai entre deux événements Mega Rocket (§6.24) |
| `MEGA_ROCKET_BASE_CASH_MULT` | `shared/MegaRocketConfig.ts` | 8 | Facteur de base cash d'un vol en Mega Rocket |
| `MEGA_ROCKET_SCALE` | `shared/MegaRocketConfig.ts` | 1.15 | Échelle de la fusée mega (`Model:ScaleTo`) |
| `TUNING` (quêtes) | `shared/QuestConfig.ts` | 3 métriques × 6 difficultés | Objectifs + récompenses ScrollToken de chaque quête (§6.26) — LE fichier de rééquilibrage |
| `QUEST_RESET_SECONDS` | `shared/QuestConfig.ts` | 300s | Cooldown avant qu'une quête accomplie ne reparte à zéro |
| `SCROLL_SHOP_ITEMS` | `shared/ScrollShopConfig.ts` | 350K/250K/50K/15K/20K/25K | Prix des 6 achats en ScrollToken (§6.27) — le prix affiché EST celui-ci |
| `SCROLL_MONEY_BOOST` | `shared/ScrollShopConfig.ts` | ×1.25 | Boost d'argent permanent acheté en tokens, additif dans `moneyMult` |
| `REFRESH_INTERVAL` | `shared/LeaderboardConfig.ts` | 60s | Leaderboard/podium refresh period |
| `TOP_N` | `shared/LeaderboardConfig.ts` | 50 | Entries stored/shown per leaderboard |
| `VISIBLE_ROWS` | `shared/LeaderboardConfig.ts` | 15 | Rows visible before scrolling |

## 9. Cheats (`server/modules/CheatConfig.ts`, `client/ClientCheatConfig.ts`)

Dev-only flags — **must be `false`/disabled before publishing**:
- `invincible` — button never explodes.
- `logExplosionForecast` — prints the flight's already-rolled outcome to the server console at
  liftoff: seconds until the explosion, the multiplier the run will have reached by then
  (`multiplierAfter`, the same loop the live multiplier runs), the matching cash, and the
  timestamp past which a claim counts as a Perfect Claim (§6.3). State **at liftoff** — a
  scripted tutorial run can rewrite its deadline on claim.
- `boostCriticalClaim` + `boostedCriticalClaimChance` — raises the Critical Claim roll from
  `CRITICAL_CLAIM_CHANCE` (5 %) to 50 % so the golden flash + icon rain (§6.22/§6.23) show up
  almost every other claim instead of once in twenty (§6.3).
- `resetData` — wipe persisted data on join (fresh default profile each time).
- `ignoreGamePasses` — when on, `BoostService` seeds every player with an empty owned-pass set
  on join, so you start exactly like a player who never bought any game pass even on an account
  that owns every pass. Takes priority over `simulateGamePasses` (§6.6).
- `simulateGamePasses` + `simulatedOwnedPassIds` — when on, `BoostService` ignores real
  game-pass ownership and treats only the listed ids as owned (empty = own nothing), so the
  buy flow can be tested from a not-owned state even on an account that owns every pass (§6.6).
- `forceTutorial` — le tutorial rejoue à la connexion en ignorant la sauvegarde tuto.
- `megaRocketInterval` — raccourcit l'intervalle entre deux Mega Rockets (§6.24) pour voir
  l'événement en quelques secondes. `undefined` = intervalle normal (6 min).
- `megaRocketCheatKey` + `megaRocketCheatDelay` — autorise la touche **G** du client à ramener
  le compte à rebours de la Mega Rocket à 3 s (§6.24). Quand le flag est faux, le serveur ne
  branche pas `MegaRocketCheatEvent` : la touche est sans effet même si le client l'envoie.
- `questCheatKey` + `questCheatTokens` — autorise la touche **U** du client à terminer la
  première quête disponible par le chemin normal (récompense, bandeau Epic et pluie d'icônes
  compris) puis à créditer 100K ScrollToken, de quoi tester la boutique (§6.27) sans farmer.
  Quand le flag est faux, `QuestCheatEvent` n'est même pas branché.
- `dailyRewardCheatKey` — ouvre le popup Daily Rewards à **chaque** connexion, récompense déjà
  prise ou non (§6.25), et autorise la touche **P** du client. La règle du tutorial reste
  appliquée : tant que le tutorial tourne, le popup est toujours reporté.

Cheats **client** (`client/ClientCheatConfig.ts`) — un module client ne peut pas importer
`ServerScriptService`, d'où le fichier séparé :
- `informationTextKeys` — touches **J / K / L / M** = bandeau de test Common / Rare / Epic /
  Legendary (`client/ui/InformationTextTest.ts`, §6.20). Appuyer plusieurs fois pour vérifier
  l'empilement. ⚠️ éviter U/I/O/P : **I et O sont les touches de zoom caméra par défaut de
  Roblox**, elles arrivent toujours avec `gameProcessed = true`.
- `megaRocketKey` — touche **G** = « Mega Rocket dans 3 s » (`client/MegaRocketCheat.ts`,
  §6.24). Le garde serveur `megaRocketCheatKey` doit lui aussi être vrai.
- `questFinishKey` — touche **U** = « termine une quête + 100K tokens »
  (`client/QuestCheat.ts`, §6.26/§6.27). Le garde serveur `questCheatKey` doit lui aussi être
  vrai. Comme la touche P ci-dessous, ce handler **ne filtre pas** sur `gameProcessed` (la
  touche est demandée explicitement) et n'écarte que le cas « le joueur écrit dans un champ ».
- `dailyRewardKey` — touche **P** = « la récompense journalière avance d'un jour »
  (`client/DailyRewardCheat.ts`, §6.25). Le garde serveur `dailyRewardCheatKey` doit lui aussi
  être vrai. Seule exception à l'avertissement U/I/O/P ci-dessus : la touche est demandée
  explicitement, donc ce handler **ne filtre pas** sur `gameProcessed` (il écarte uniquement le
  cas « le joueur écrit dans un champ de texte » via `GetFocusedTextBox`).

## 10. Conventions (see also `CLAUDE.md`)

- Strong typing; avoid `any`. Prefer simple, readable, single-responsibility files.
- Don't rewrite working systems; modify only what the task needs (CLAUDE.md refactoring rules).
- Server authoritative; keep client/server responsibilities separate.
- Absolute imports from `src/` (`server/…`, `client/…`, `shared/…`).
- Comments may be EN or FR (codebase is mixed); match the surrounding file.
- Mobile players supported by default; consider performance.
```

