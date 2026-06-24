# Money Multipliers on Base Cash — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the rebirth multiplier off the payout and onto the displayed Base Cash, generalised to three independent **additive** factors (rebirth + money game-pass tier + community ×2) plus a safety game pass (+20%), all server-verified.

**Architecture:** Levels stay the persisted source of truth (`PlayerProgressionService`); a new `deriveValues()` folds the factors into two replicated attributes — `MoneyMult` (additive total) and `EffectiveBaseCash = floor(BaseCash × MoneyMult)` — and into `AdditionalSecurity` (now incl. the safety pass). A new `BoostService` resolves group membership + game-pass ownership (web calls, pcall-guarded, id 0 = inert) into input attributes and calls `recompute`. The button payout reads `EffectiveBaseCash` and drops the payout-time `multRebirth`. Community is claimed via a `CommunityJoinPart` ProximityPrompt per room.

**Tech Stack:** Roblox-TS (`rbxtsc`), Rojo, player Attributes for replication, `MarketplaceService` / `Player:IsInGroup` for ownership, Roblox_Studio MCP for in-Studio verification + GUI/part authoring.

## Global Constraints

- **Additive bonus model:** `MoneyMult = MultRebirth + (inCommunity ? COMMUNITY.mult−1 : 0) + (MoneyTierMult−1)`. Each "×N" adds `+(N−1)`; a lone factor keeps its value; a fresh player = ×1.
- **Money tiers:** highest owned tier wins (ladder, not stacked). Max ×1024.
- **Community:** Roblox group `963505568`, `Player:IsInGroup`. Claimed via `CommunityJoinPart` prompt.
- **Safety cap:** `SAFETY_TOTAL_CAP = 0.70` (shop 0.50 + pass 0.20).
- **Game-pass IDs are `0` = INERT** (no web call, treated not-owned, buttons do nothing) until real IDs are set on the dashboard.
- **No DataStore migration:** boosts are resolved live each session, never persisted. `Rebirths`/levels unchanged.
- **`out/` is generated** by `npm run build` — never hand-edit. Commit `src/` + rebuilt `out/` together.
- Strong typing, avoid `any`; comments EN/FR per surrounding file (codebase is mixed).

---

## Verification approach (no unit-test runner)

`package.json` has only `build` / `watch` — no test framework. Each task is verified by:

1. **Type-check gate** — `npm run build` completes with **no errors** (exit 0). Primary automated net.
2. **Pure-logic checks** — after building + Rojo sync, use Roblox_Studio MCP `execute_luau` to `require` a compiled module from `game.ReplicatedStorage.TS.<Module>` and assert exact values.
3. **Playtest checkpoints** — for gameplay/UI, run the game in Studio and follow the steps.

> **Calling compiled service methods from `execute_luau`:** object methods (e.g. `recompute`) compile with an implicit `self` — call them with `:` (e.g. `Prog:recompute(p)`), not `.` (project memory). Plain exported functions in shared modules (e.g. `ShopConfig.moneyMult`) take no self — call with `.`.

> **Cheat note:** `resetData` in `src/server/modules/CheatConfig.ts` is `true`, so every join starts fresh — convenient here. Leave as-is; it's already flagged for disabling before shipping.

> **Studio GUI path:** the in-game UI ScreenGui is `StarterGui.InGameUI` (verified by inspection — an older plan said `MainUI`; trust `InGameUI`).

---

## File structure

| File | Responsibility | Action |
|------|----------------|--------|
| `src/shared/ShopBalance.ts` | `COMMUNITY`, `MONEY_TIERS`, `SAFETY_PASS`, `SAFETY_TOTAL_CAP` numbers | Modify |
| `src/shared/ShopConfig.ts` | Pure helpers `moneyMult`, `effectiveSafety`, `nextMoneyTier` | Modify |
| `src/server/services/PlayerProgressionService.ts` | `deriveValues`/`recompute`; new `ProgressionKey`s; call recompute on load/addLevel/rebirth | Modify |
| `src/server/services/BoostService.ts` | Resolve group + game-pass → input attrs → recompute | Create |
| `src/server/services/index.ts` | Boot `BoostService` after `PlayerProgressionService` | Modify |
| `src/server/modules/ButtonInGameModule.ts` | Read `EffectiveBaseCash`; drop `multRebirth` from 4 payouts | Modify |
| `src/server/modules/EndGameButtonModule.ts` | Drop `multRebirth` param + event arg | Modify |
| `src/client/behaviors/EndGameButtonBehavior.ts` | Drop `multRebirth` arg | Modify |
| `src/client/ui/EndGameAnimation.ts` | Drop `multRebirth`; remove gold rebirth phase | Modify |
| `src/server/rooms/Room.ts` | Resolve optional `communityJoinPrompt` | Modify |
| `src/server/rooms/RoomService.ts` | Mirror `EffectiveBaseCash`; wire `CommunityJoinPart` prompt | Modify |
| `src/client/behaviors/BoostShopController.ts` | Shop multiplier readout + safety/tier Robux buttons | Create |
| `src/client/main.client.ts` | Init `BoostShopController` | Modify |
| Studio | Duplicate `CommunityJoinPart` to P2–P10; readout label; prompt text | Author |
| `ARCHITECTURE.md` | Keep docs in sync | Modify |

Task order respects dependencies: 1 (numbers) → 2 (helpers) → 3 (derive) → 4 (boost detection) → 5 (payout) → 6 (billboard + community prompt) → 7 (shop UI) → 8 (docs).

---

## Task 1: Money-multiplier config in ShopBalance

**Files:**
- Modify: `src/shared/ShopBalance.ts`

**Interfaces:**
- Produces: `COMMUNITY: { groupId: number; mult: number }`, `MONEY_TIERS: ReadonlyArray<{ mult: number; gamePassId: number }>`, `SAFETY_PASS: { add: number; gamePassId: number }`, `SAFETY_TOTAL_CAP: number`.

- [ ] **Step 1: Append the config block**

Add at the end of `src/shared/ShopBalance.ts`:

```ts
// ── Money multipliers (3 independent additive factors) ────────────────────────
// Folded into BaseCash via shared/ShopConfig.moneyMult (additive bonus model:
// each "×N" adds +(N-1)). Game-pass IDs are 0 until authored on the Roblox
// dashboard — an id of 0 is INERT (treated as not owned, no web call).

// Community ×2 — membership of the experience's Roblox group, claimed via the
// CommunityJoinPart ProximityPrompt in each room.
export const COMMUNITY = { groupId: 963505568, mult: 2 };

// Money game-pass ladder — the HIGHEST owned tier wins (not stacked). Each value
// is the TOTAL multiplier of that tier (×2 … ×1024).
export const MONEY_TIERS: ReadonlyArray<{ mult: number; gamePassId: number }> = [
	{ mult: 2, gamePassId: 0 },
	{ mult: 4, gamePassId: 0 },
	{ mult: 8, gamePassId: 0 },
	{ mult: 16, gamePassId: 0 },
	{ mult: 32, gamePassId: 0 },
	{ mult: 64, gamePassId: 0 },
	{ mult: 128, gamePassId: 0 },
	{ mult: 256, gamePassId: 0 },
	{ mult: 512, gamePassId: 0 },
	{ mult: 1024, gamePassId: 0 },
];

// Safety game pass — flat risk reduction added on top of the shop Safety.
export const SAFETY_PASS = { add: 0.2, gamePassId: 0 };

// Cumulative safety cap: shop (0.50) + pass (0.20). Keeps risk floored at ×0.30.
export const SAFETY_TOTAL_CAP = 0.7;
```

- [ ] **Step 2: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 3: Verify the constants in Studio (after Rojo sync)**

`execute_luau` (datamodel: Edit):

```lua
local SB = require(game.ReplicatedStorage.TS.ShopBalance)
return {
  group = SB.COMMUNITY.groupId,        -- 963505568
  commMult = SB.COMMUNITY.mult,        -- 2
  tiers = #SB.MONEY_TIERS,             -- 10
  topTier = SB.MONEY_TIERS[10].mult,   -- 1024
  safeAdd = SB.SAFETY_PASS.add,        -- 0.2
  cap = SB.SAFETY_TOTAL_CAP,           -- 0.7
}
```
Expected: `group=963505568, commMult=2, tiers=10, topTier=1024, safeAdd=0.2, cap=0.7`. (If Studio isn't running, the Step 2 build is the minimum gate.)

- [ ] **Step 4: Commit**

```bash
git add src/shared/ShopBalance.ts out/shared/ShopBalance.luau
git commit -m "feat(economy): config multiplicateurs argent (communauté, paliers, safety pass)"
```

---

## Task 2: Pure money-multiplier helpers in ShopConfig

**Files:**
- Modify: `src/shared/ShopConfig.ts`

**Interfaces:**
- Consumes: `COMMUNITY`, `MONEY_TIERS`, `SAFETY_PASS`, `SAFETY_TOTAL_CAP` (Task 1).
- Produces: `moneyMult(multRebirth: number, moneyTierMult: number, inCommunity: boolean): number`; `effectiveSafety(shopSafety: number, hasSafetyPass: boolean): number`; `nextMoneyTier(currentMult: number): { mult: number; gamePassId: number } | undefined`.

- [ ] **Step 1: Extend the ShopBalance import**

In `src/shared/ShopConfig.ts`, change the import on line 2:

```ts
import {
	BASE_CASH,
	COMMUNITY,
	MONEY_TIERS,
	MULTIPLIER,
	PRICE_GROWTH,
	REBIRTH,
	SAFETY,
	SAFETY_PASS,
	SAFETY_TOTAL_CAP,
} from "./ShopBalance";
```

- [ ] **Step 2: Append the helpers**

Add at the end of `src/shared/ShopConfig.ts`:

```ts
// ── Money multipliers — additive bonus model (pure, shared client/server) ──────
// ADDITIVE: each "×N" factor contributes "+(N-1)", so a lone factor keeps its
// labelled value and a brand-new player stays ×1. MultRebirth (≥1) carries the
// base 1. Any future independent multiplier adds its own (mult-1) the same way.
//   moneyMult = MultRebirth + (inCommunity ? COMMUNITY.mult-1 : 0) + (moneyTierMult-1)
export function moneyMult(multRebirth: number, moneyTierMult: number, inCommunity: boolean): number {
	const communityBonus = inCommunity ? COMMUNITY.mult - 1 : 0;
	const tierBonus = moneyTierMult - 1;
	return multRebirth + communityBonus + tierBonus;
}

// Effective safety used by the risk loop: shop Safety + the safety game pass,
// capped (SAFETY_TOTAL_CAP) so the risk can never reach 0.
export function effectiveSafety(shopSafety: number, hasSafetyPass: boolean): number {
	const total = shopSafety + (hasSafetyPass ? SAFETY_PASS.add : 0);
	return math.min(total, SAFETY_TOTAL_CAP);
}

// The next money tier strictly above `currentMult` (for the shop upsell), or
// undefined if already at the top. Tiers are a ladder — the highest owned wins.
export function nextMoneyTier(currentMult: number): { mult: number; gamePassId: number } | undefined {
	for (const tier of MONEY_TIERS) {
		if (tier.mult > currentMult) return tier;
	}
	return undefined;
}
```

- [ ] **Step 3: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 4: Verify the additive math in Studio**

`execute_luau` (Edit) — these are the spec's worked numbers:

```lua
local SC = require(game.ReplicatedStorage.TS.ShopConfig)
return {
  fresh    = SC.moneyMult(1, 1, false),      -- 1  (fresh player unchanged)
  rebirth2 = SC.moneyMult(2, 1, false),      -- 2
  comm     = SC.moneyMult(1, 1, true),       -- 2  (community alone = its value)
  tier4    = SC.moneyMult(1, 4, false),      -- 4  (tier alone = its value)
  all      = SC.moneyMult(2, 4, true),       -- 6  (2 + 1 + 3, NOT 16)
  safe     = SC.effectiveSafety(0.5, true),  -- 0.7
  safeCap  = SC.effectiveSafety(0.6, true),  -- 0.7 (capped)
  noPass   = SC.effectiveSafety(0.5, false), -- 0.5
  nextOf2  = SC.nextMoneyTier(2).mult,       -- 4
  nextTop  = SC.nextMoneyTier(1024),         -- nil
}
```
Expected: `fresh=1, rebirth2=2, comm=2, tier4=4, all=6, safe=0.7, safeCap=0.7, noPass=0.5, nextOf2=4, nextTop=nil`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/ShopConfig.ts out/shared/ShopConfig.luau
git commit -m "feat(economy): helpers purs moneyMult / effectiveSafety / nextMoneyTier (additif)"
```

---

## Task 3: Derive EffectiveBaseCash + MoneyMult in PlayerProgressionService

**Files:**
- Modify: `src/server/services/PlayerProgressionService.ts`

**Interfaces:**
- Consumes: `moneyMult`, `effectiveSafety` (Task 2); existing `STATS`, `rebirthMult`.
- Produces: input attrs read here (defaulted) `InCommunity` (bool), `MoneyTierMult` (number), `HasSafetyPass` (bool); derived attrs `MoneyMult`, `EffectiveBaseCash`; `PlayerProgressionService.recompute(player: Player): void`; `get(player, "EffectiveBaseCash" | "MoneyMult")`.

`deriveValues()` is a free function (so the free `applyLevels` and the methods can all call it); `recompute` is the public method `BoostService` calls. The Safety loop in `applyLevels`/`addLevel` sets `AdditionalSecurity` to the *raw* shop value first; `deriveValues` then overwrites it with the pass-inclusive value.

- [ ] **Step 1: Extend the ShopConfig import + add attribute constants**

Change the import on line 3:

```ts
import { ShopStat, STATS, rebirthMult, moneyMult, effectiveSafety } from "shared/ShopConfig";
```

Immediately after the existing `MULT_REBIRTH_ATTR` constant (line ~22), add:

```ts
// Boost input attributes (written by BoostService; defaulted here so deriveValues
// is safe before BoostService resolves). game.ts reads the derived attrs below.
const IN_COMMUNITY_ATTR = "InCommunity";
const MONEY_TIER_MULT_ATTR = "MoneyTierMult";
const HAS_SAFETY_PASS_ATTR = "HasSafetyPass";
// Derived, replicated for the game loop / billboard / shop readout.
const MONEY_MULT_ATTR = "MoneyMult";
const EFFECTIVE_BASE_CASH_ATTR = "EffectiveBaseCash";
```

- [ ] **Step 2: Extend `ProgressionKey` + `DEFAULT_VALUES`**

Replace the `ProgressionKey` type (line ~25) and `DEFAULT_VALUES` (line ~28):

```ts
export type ProgressionKey = "BaseCash" | "Multiplier" | "AdditionalSecurity" | "EffectiveBaseCash" | "MoneyMult";

// Fallback values if a value attribute is somehow missing (matches level 0).
const DEFAULT_VALUES: { readonly [K in ProgressionKey]: number } = {
	BaseCash: 100,
	Multiplier: 0.1,
	AdditionalSecurity: 0,
	EffectiveBaseCash: 100,
	MoneyMult: 1,
};
```

- [ ] **Step 3: Add the `deriveValues` free function**

Add immediately after `applyLevels` is *declared* (i.e. just below the closing `}` of `applyLevels`, before `loadLevels`):

```ts
// Folds the boost inputs into the replicated derived values. Additive money
// multiplier (shared/ShopConfig.moneyMult) → EffectiveBaseCash; safety pass →
// AdditionalSecurity. Reads level/rebirth/input attributes already set on the
// player. Called after every state change (load, purchase, rebirth, boost
// resolve) so the billboard / game loop / shop read one source of truth.
function deriveValues(player: Player): void {
	const baseCashLevel = (player.GetAttribute(STATS.BaseCash.levelAttribute) as number | undefined) ?? 0;
	const rawBase = STATS.BaseCash.valueFor(baseCashLevel);
	const multRebirth = (player.GetAttribute(MULT_REBIRTH_ATTR) as number | undefined) ?? rebirthMult(0);
	const tierMult = (player.GetAttribute(MONEY_TIER_MULT_ATTR) as number | undefined) ?? 1;
	const inCommunity = player.GetAttribute(IN_COMMUNITY_ATTR) === true;

	const mMult = moneyMult(multRebirth, tierMult, inCommunity);
	player.SetAttribute(MONEY_MULT_ATTR, mMult);
	player.SetAttribute(EFFECTIVE_BASE_CASH_ATTR, math.floor(rawBase * mMult));

	const safetyLevel = (player.GetAttribute(STATS.Safety.levelAttribute) as number | undefined) ?? 0;
	const rawSafety = STATS.Safety.valueFor(safetyLevel);
	const hasPass = player.GetAttribute(HAS_SAFETY_PASS_ATTR) === true;
	player.SetAttribute(STATS.Safety.valueAttribute, effectiveSafety(rawSafety, hasPass));
}
```

- [ ] **Step 4: Call `deriveValues` after each state change**

At the **end of `applyLevels`** (after the `MULT_REBIRTH_ATTR` SetAttribute line), add:

```ts
	deriveValues(player);
```

At the **end of `addLevel`** (after `player.SetAttribute(cfg.valueAttribute, cfg.valueFor(nextLevel));`), add:

```ts
		deriveValues(player);
```

At the **end of `rebirth`** (after the `MULT_REBIRTH_ATTR` SetAttribute line), add:

```ts
		deriveValues(player);
```

- [ ] **Step 5: Expose the `recompute` method**

Inside the `PlayerProgressionService` object, add (e.g. after `getMultRebirth`):

```ts
	// Re-derives MoneyMult / EffectiveBaseCash / AdditionalSecurity from the
	// current level + rebirth + boost-input attributes. Called by BoostService
	// after it writes the input attributes (group / game-pass ownership).
	recompute(player: Player): void {
		deriveValues(player);
	},
```

- [ ] **Step 6: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 7: Verify in Studio (Play mode, a player present)**

Start a playtest, then `execute_luau` (datamodel: Server):

```lua
local p = game:GetService("Players"):GetPlayers()[1]
local Prog = require(game.ServerScriptService.TS.services.PlayerProgressionService).PlayerProgressionService
-- fresh: EffectiveBaseCash == BaseCash, MoneyMult == 1
local base = p:GetAttribute("BaseCash")
local eff0 = p:GetAttribute("EffectiveBaseCash")
local mult0 = p:GetAttribute("MoneyMult")
-- simulate rebirth ×2 + community + tier ×4
p:SetAttribute("MultRebirth", 2)
p:SetAttribute("InCommunity", true)
p:SetAttribute("MoneyTierMult", 4)
Prog:recompute(p)            -- ':' — compiled method takes self
return {
  base = base, eff0 = eff0, mult0 = mult0,         -- eff0==base, mult0==1
  moneyMult = p:GetAttribute("MoneyMult"),         -- 6
  eff = p:GetAttribute("EffectiveBaseCash"),       -- floor(base * 6)
}
```
Expected: `eff0 == base`, `mult0 == 1`, `moneyMult == 6`, `eff == math.floor(base * 6)`.

- [ ] **Step 8: Commit**

```bash
git add src/server/services/PlayerProgressionService.ts out/server/services/PlayerProgressionService.luau
git commit -m "feat(progression): dériver MoneyMult / EffectiveBaseCash (additif) + safety pass"
```

---

## Task 4: BoostService — resolve group + game-pass ownership

**Files:**
- Create: `src/server/services/BoostService.ts`
- Modify: `src/server/services/index.ts`

**Interfaces:**
- Consumes: `COMMUNITY`, `MONEY_TIERS`, `SAFETY_PASS` (Task 1); `PlayerProgressionService.recompute` (Task 3).
- Produces: `BoostService.init()`; `BoostService.refreshCommunity(player: Player): void` (called by RoomService, Task 6).

- [ ] **Step 1: Create `BoostService.ts`**

Create `src/server/services/BoostService.ts`:

```ts
import { MarketplaceService, Players } from "@rbxts/services";
import { COMMUNITY, MONEY_TIERS, SAFETY_PASS } from "shared/ShopBalance";
import { PlayerProgressionService } from "./PlayerProgressionService";

// Owns detection of EXTERNAL boosts — Roblox group membership + game-pass
// ownership — and writes the input attributes PlayerProgressionService folds into
// the money multiplier / effective base cash. Web calls (IsInGroup,
// UserOwnsGamePassAsync) yield and can fail, so each is pcall-guarded. A game-pass
// id of 0 is INERT (no web call, treated not-owned) until a real id is configured.

const IN_COMMUNITY_ATTR = "InCommunity";
const MONEY_TIER_MULT_ATTR = "MoneyTierMult";
const HAS_SAFETY_PASS_ATTR = "HasSafetyPass";

function ownsGamePass(userId: number, gamePassId: number): boolean {
	if (gamePassId <= 0) return false; // inert until a real id is set
	const [ok, owns] = pcall(() => MarketplaceService.UserOwnsGamePassAsync(userId, gamePassId));
	return ok && owns === true;
}

// Highest owned money tier's multiplier (ladder — top tier wins). 1 if none.
function resolveTierMult(userId: number): number {
	let best = 1;
	for (const tier of MONEY_TIERS) {
		if (tier.mult > best && ownsGamePass(userId, tier.gamePassId)) best = tier.mult;
	}
	return best;
}

function isInCommunity(player: Player): boolean {
	const [ok, result] = pcall(() => player.IsInGroup(COMMUNITY.groupId));
	return ok && result === true;
}

// Synchronous defaults so the attributes exist immediately on join (before the
// async web calls return) — keeps deriveValues + the client shop readout sane.
function setDefaults(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, false);
	player.SetAttribute(MONEY_TIER_MULT_ATTR, 1);
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, false);
	PlayerProgressionService.recompute(player);
}

// Full resolve — group + all game passes. Yields (web calls); run in task.spawn.
function resolve(player: Player): void {
	const userId = player.UserId;
	player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));
	player.SetAttribute(MONEY_TIER_MULT_ATTR, resolveTierMult(userId));
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, ownsGamePass(userId, SAFETY_PASS.gamePassId));
	PlayerProgressionService.recompute(player);
}

export const BoostService = {
	init(): void {
		const onAdded = (player: Player): void => {
			setDefaults(player); // sync — attributes exist right away
			task.spawn(() => resolve(player)); // async — web calls
		};
		Players.PlayerAdded.Connect(onAdded);
		for (const player of Players.GetPlayers()) onAdded(player);

		// A successful game-pass purchase → re-resolve that player's ownership.
		MarketplaceService.PromptGamePassPurchaseFinished.Connect((player, _gamePassId, purchased) => {
			if (purchased) task.spawn(() => resolve(player));
		});
	},

	// Re-check ONLY community membership (the player joined the group then
	// triggered the CommunityJoinPart prompt). Called by RoomService. Yields.
	refreshCommunity(player: Player): void {
		player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));
		PlayerProgressionService.recompute(player);
	},
};
```

- [ ] **Step 2: Boot `BoostService` after `PlayerProgressionService`**

In `src/server/services/index.ts`, add the import alongside the others:

```ts
import { BoostService } from "./BoostService";
```

Insert it into the `services` array immediately after `PlayerProgressionService`:

```ts
	PlayerProgressionService,
	// External boosts (group ×2 + money/safety game passes) → input attributes,
	// then recompute. After Progression (needs recompute), before RoomService.
	BoostService,
	// Shop needs PlayerData (money) + PlayerProgression (levels) ready first.
	ShopService,
```

- [ ] **Step 3: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 4: Verify in Studio (Play mode)**

`execute_luau` (Server). The signed-in Studio account's real membership of group 963505568 drives `InCommunity`; game-pass ids are 0 so the tier stays 1 and the pass false:

```lua
local p = game:GetService("Players"):GetPlayers()[1]
return {
  inCommunity = p:GetAttribute("InCommunity"),   -- true/false per your group membership
  tierMult = p:GetAttribute("MoneyTierMult"),     -- 1 (ids are 0)
  hasPass = p:GetAttribute("HasSafetyPass"),      -- false (id is 0)
  moneyMult = p:GetAttribute("MoneyMult"),        -- 1, or 2 if you're in the group
  eff = p:GetAttribute("EffectiveBaseCash"),      -- floor(BaseCash * MoneyMult)
}
```
Then exercise the community re-check directly:

```lua
local p = game:GetService("Players"):GetPlayers()[1]
local Boost = require(game.ServerScriptService.TS.services.BoostService).BoostService
Boost:refreshCommunity(p)                          -- ':' — compiled method
return { inCommunity = p:GetAttribute("InCommunity"), moneyMult = p:GetAttribute("MoneyMult") }
```
Expected: `inCommunity` matches whether the Studio account is in group 963505568; if member, `moneyMult` includes the `+1` community bonus.

- [ ] **Step 5: Commit**

```bash
git add src/server/services/BoostService.ts src/server/services/index.ts out/server/services/BoostService.luau out/server/services/init.luau
git commit -m "feat(boost): BoostService détecte groupe + game pass → attributs d'entrée"
```

---

## Task 5: Payout reads EffectiveBaseCash, drops multRebirth (end-to-end)

**Files:**
- Modify: `src/server/modules/ButtonInGameModule.ts`
- Modify: `src/server/modules/EndGameButtonModule.ts`
- Modify: `src/client/behaviors/EndGameButtonBehavior.ts`
- Modify: `src/client/ui/EndGameAnimation.ts`

The payout base becomes `EffectiveBaseCash` (already boosted) and `multRebirth` is removed from the four payout formulas, the `enter()` signature, the `EndGameStartEvent` payload, the client handler and the animation. The gold "xN rebirth" phase (2b) is deleted. This is **one task** because the `EndGameStartEvent` payload change must land on server + client together.

- [ ] **Step 1: Read `EffectiveBaseCash`, drop the `multRebirth` read (ButtonInGameModule)**

In `startButtonGame` (around lines 108–118), replace the BaseCash read and delete the multRebirth read so the block reads:

```ts
	// EffectiveBaseCash already folds in every money multiplier (rebirth + money
	// game-pass tier + community), additively. Read once — held for the session so
	// a mid-run boost change can't alter an in-progress hold.
	const baseCash = PlayerProgressionService.get(player, "EffectiveBaseCash");

	const multiplierPerSecond = PlayerProgressionService.get(player, "Multiplier");
	// Safety (0..0.70 with the pass) scales the explosion risk down. Read once.
	const safety = PlayerProgressionService.get(player, "AdditionalSecurity");
```

(Delete the three `multRebirth` lines that followed the `safety` line.)

- [ ] **Step 2: Drop `multRebirth` from the four payout sites (ButtonInGameModule)**

**Site 1 — release handler:**

```ts
		const earned = math.floor(baseCash * currentMultiplier);
		Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
		ConfettiBurst.play(buttonModel);
		EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
```

**Site 2 — grace-period cancel (inside `if (cancelledByPlayer)`):**

```ts
					const earned = math.floor(baseCash * currentMultiplier);
					Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
					ConfettiBurst.play(buttonModel);
					EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
```

**Site 3 — parry success (inside `if (isPerfectParry)`, after the knockback):**

```ts
						const earned = math.floor(baseCash * currentMultiplier);
						Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
						EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
```

**Site 4 — death (the parry `else`):**

```ts
						const earned = math.floor(baseCash * LOOSE_WIN_MULTIPLIER * currentMultiplier);
						Events.GameResultEvent.FireClient(player, true, earned, currentMultiplier);
						EndGameButtonModule.enter(
							player,
							"killed",
							baseCash,
							currentMultiplier,
							earned,
							LOOSE_WIN_MULTIPLIER,
						);
```

- [ ] **Step 3: Drop the `multRebirth` param + event arg (EndGameButtonModule)**

In `src/server/modules/EndGameButtonModule.ts`, remove `multRebirth: number,` from the `enter(...)` signature so it ends:

```ts
	enter(
		player: Player,
		mode: EndGameMode,
		baseCash: number,
		multiplier: number,
		earned: number,
		lossMultiplier: number,
	): void {
```

And drop `multRebirth` from the event fire:

```ts
			Events.EndGameStartEvent.FireClient(player, baseCash, multiplier, lossMultiplier);
```

- [ ] **Step 4: Drop the `multRebirth` arg on the client (EndGameButtonBehavior)**

In `src/client/behaviors/EndGameButtonBehavior.ts`, update the handler signature and the animation call:

```ts
	Events.EndGameStartEvent.OnClientEvent.Connect(
		(baseCash: number, multiplier: number, lossMultiplier: number) => {
			InGameUIController.enable();
			ButtonAnimations.restoreDefault();

			const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
			const inGameUI = playerGui.WaitForChild("InGameUI") as ScreenGui;
			const frame = inGameUI.WaitForChild("ButtonFinishGame") as Frame;

			task.spawn(() => {
				runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, () => {
					Events.EndGameFinishedEvent.FireServer();
					MusicController.resumeBgm();
				});
			});
		},
	);
```

- [ ] **Step 5: Drop `multRebirth` + remove the gold rebirth phase (EndGameAnimation)**

In `src/client/ui/EndGameAnimation.ts`:

**(a)** Delete the now-unused tuning constants (the Phase 2b block, lines ~52–57):

```ts
// Phase 2b — rebirth multiplier floating text (only when the player has rebirthed).
const REBIRTH_MERGE_TI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const REBIRTH_COUNTUP_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const REBIRTH_LABEL_COLOR = new Color3(1, 0.82, 0.2); // gold — sets it apart from the in-game multiplier
const REBIRTH_LABEL_START_OFFSET = 120; // px above BaseCashText where the rebirth text spawns
const REBIRTH_COUNTUP_SIZE_RATIO = 0.6; // share of the size growth done in phase 2a (rest in 2b)
```

**(b)** Delete the `formatRebirthMultiplier` helper (lines ~71–73):

```ts
// Rebirth multiplier label — "x2", "x3.5". Prefix form distinguishes it from the
// in-game multiplier's "{n}x".
function formatRebirthMultiplier(value: number): string {
	return `x${tostring(math.round(value * 10) / 10)}`;
}
```

**(c)** Delete the entire `flyRebirthMultiplierIntoBaseCash` function (the block starting `// ── Phase 2b: rebirth multiplier text flies into BaseCashText (blocking) ─` through its closing `}`, lines ~212–242).

**(d)** Remove `multRebirth` from the `runEndGameAnimation` signature:

```ts
export function runEndGameAnimation(
	frame: Frame,
	baseCash: number,
	multiplier: number,
	lossMultiplier: number,
	onComplete: () => void,
): void {
```

**(e)** Replace the Phase 2a/2b block (the `// ── Phase 2a:` section, lines ~366–381) with a single count-up:

```ts
	// ── Phase 2: BaseCashText counts up by the in-game multiplier ─────────────────
	// EffectiveBaseCash already includes every money multiplier (rebirth + tier +
	// community), so the start number shows the boost — no separate rebirth phase.
	const totalEarn = effectiveBaseCash * multiplier;
	const grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE;
	animateCash(
		baseCashText,
		effectiveBaseCash,
		totalEarn,
		effectiveBaseSize,
		grownSize,
		baseColor,
		BASE_CASH_TARGET_COLOR,
		BASE_CASH_COUNTUP_TI,
	);
```

- [ ] **Step 6: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0). If it reports an unused symbol (`screenGui` is still used by Phase 3 / `spawnFloatingChunk`, so it stays), re-check that only the rebirth items above were removed.

- [ ] **Step 7: Playtest (boosted base flows through payout + animation)**

Studio Play mode, fresh player (MoneyMult = 1, or 2 if your account is in the group):
1. Trigger the button, hold a few seconds, release.
2. The end-game number counts up from the **EffectiveBaseCash** (HUD base label matches the button billboard once Task 6 lands) and there is **no gold "xN" fly-in**.
3. Credited money equals the displayed total = `floor(EffectiveBaseCash × multiplier)`.

Then scale a factor and confirm:

```lua
local p = game:GetService("Players"):GetPlayers()[1]
p:SetAttribute("MoneyTierMult", 4)
local Prog = require(game.ServerScriptService.TS.services.PlayerProgressionService).PlayerProgressionService
Prog:recompute(p)
return { eff = p:GetAttribute("EffectiveBaseCash"), moneyMult = p:GetAttribute("MoneyMult") }
```
Play another round: the payout scales with the higher `EffectiveBaseCash`, and the animated total still equals the credited money.

- [ ] **Step 8: Commit**

```bash
git add src/server/modules/ButtonInGameModule.ts src/server/modules/EndGameButtonModule.ts src/client/behaviors/EndGameButtonBehavior.ts src/client/ui/EndGameAnimation.ts out/server/modules/ButtonInGameModule.luau out/server/modules/EndGameButtonModule.luau out/client/behaviors/EndGameButtonBehavior.luau out/client/ui/EndGameAnimation.luau
git commit -m "feat(payout): payer depuis EffectiveBaseCash, retirer multRebirth + phase or"
```

---

## Task 6: Billboard mirrors EffectiveBaseCash + CommunityJoinPart prompt

**Files:**
- Modify: `src/server/rooms/Room.ts`
- Modify: `src/server/rooms/RoomService.ts`
- Studio: duplicate `CommunityJoinPart` into P2–P10

**Interfaces:**
- Consumes: `PlayerProgressionService.get(player, "EffectiveBaseCash")` (Task 3); `BoostService.refreshCommunity` (Task 4).
- Produces: `Room.communityJoinPrompt: ProximityPrompt | undefined`.

- [ ] **Step 1: Resolve the optional prompt in `Room.ts`**

Add the name constant near the other folder-child names (after `OWNER_INDICATOR_PART`, line ~29):

```ts
const COMMUNITY_JOIN_PART = "CommunityJoinPart";
```

Add the field next to `billboardGui` (line ~39):

```ts
	readonly communityJoinPrompt: ProximityPrompt | undefined;
```

At the end of the constructor (after the owner-display block, before the closing `}`), resolve it:

```ts
		// Optional "join the community for ×2" prompt — a CommunityJoinPart sibling
		// of the ButtonModel, holding a ProximityPrompt. RoomService wires its
		// Triggered to BoostService (re-checks the triggerer's group membership).
		const communityJoinPart = folder.FindFirstChild(COMMUNITY_JOIN_PART);
		const joinPrompt = communityJoinPart?.FindFirstChildOfClass("ProximityPrompt");
		if (joinPrompt) this.communityJoinPrompt = joinPrompt;
```

- [ ] **Step 2: Mirror `EffectiveBaseCash` + wire the prompt in `RoomService.ts`**

Add the import (after the `RoomSpotlights` import, line ~5):

```ts
import { BoostService } from "server/services/BoostService";
```

In `assign(player)`, change the initial billboard value (line ~52):

```ts
	room.setGainCash(PlayerProgressionService.get(player, "EffectiveBaseCash"));
```

And change the change-signal connection (lines ~66–69) to watch `EffectiveBaseCash`:

```ts
	const conn = player.GetAttributeChangedSignal("EffectiveBaseCash").Connect(() => {
		room.setGainCash(PlayerProgressionService.get(player, "EffectiveBaseCash"));
	});
	baseCashConns.set(player, conn);
```

In `RoomService.init()`, after the room-build loop (after `rooms.push(room)` loop, before the `Players.PlayerAdded` connect), wire each room's join prompt once. It acts on whoever triggers it (claiming their own ×2), so no per-occupant gating is needed:

```ts
		// Wire each room's CommunityJoinPart prompt → re-check the triggerer's group
		// membership (grants the community ×2 if they've since joined the group).
		for (const room of rooms) {
			if (room.communityJoinPrompt) {
				room.communityJoinPrompt.Triggered.Connect((player) => BoostService.refreshCommunity(player));
			}
		}
```

- [ ] **Step 3: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 4: Duplicate `CommunityJoinPart` into P2–P10 (Studio, Edit mode)**

The part currently exists only in `Workspace.PlayerZones.P1`. Clone it into every other room at the same offset from that room's `ButtonPart`. `execute_luau` (datamodel: Edit):

```lua
local zones = workspace.PlayerZones
local p1 = zones.P1
local src = p1:FindFirstChild("CommunityJoinPart")
assert(src, "P1.CommunityJoinPart missing")
local p1Button = p1.ButtonModel.ButtonPart
local offset = p1Button.CFrame:ToObjectSpace(src.CFrame) -- src relative to P1 button
local made = {}
for _, room in ipairs(zones:GetChildren()) do
	if room ~= p1 and room:FindFirstChild("ButtonModel") and not room:FindFirstChild("CommunityJoinPart") then
		local btn = room.ButtonModel:FindFirstChild("ButtonPart")
		if btn then
			local copy = src:Clone()
			copy.CFrame = btn.CFrame * offset
			copy.Anchored = true
			copy.CanCollide = false
			copy.Parent = room
			table.insert(made, room.Name)
		end
	end
end
-- also pin P1's part
src.Anchored = true
src.CanCollide = false
return made
```
Expected: returns the list of rooms it added the part to (e.g. `{"P2","P3",...}`). Report what was created. Set the `ProximityPrompt.ActionText` (e.g. "Rejoindre la communauté (×2)") and a small `MaxActivationDistance` on `src` so only the room occupant sees it; the clones inherit it.

- [ ] **Step 5: Playtest (billboard + community claim)**

Studio Play mode:
1. The button **billboard** shows the EffectiveBaseCash (boosted) value, not the raw 100. Buy a BaseCash upgrade → it updates.
2. Walk to the `CommunityJoinPart`, trigger the prompt. `execute_luau` to confirm the re-check ran:

```lua
local p = game:GetService("Players"):GetPlayers()[1]
return { inCommunity = p:GetAttribute("InCommunity"), eff = p:GetAttribute("EffectiveBaseCash") }
```
If your Studio account is in group 963505568, `inCommunity = true` and `EffectiveBaseCash` reflects the `+1` bonus; the billboard updates live.

- [ ] **Step 6: Commit**

```bash
git add src/server/rooms/Room.ts src/server/rooms/RoomService.ts out/server/rooms/Room.luau out/server/rooms/RoomService.luau
git commit -m "feat(rooms): billboard = EffectiveBaseCash + prompt CommunityJoinPart (×2)"
```

---

## Task 7: Shop multiplier readout + safety/tier Robux buttons

**Files:**
- Create: `src/client/behaviors/BoostShopController.ts`
- Modify: `src/client/main.client.ts`
- Studio: add a `MultiplierText` readout label in `ShopMenu/Header`

The shop gets a read-only multiplier breakdown (each independent factor + total) and wires two existing-but-unused `RobuxButton`s: `AButtonMoney`'s → the next money tier upsell, `DSafety`'s → the safety pass. Both are **inert while their game-pass id is 0** (they show a "soon" state and do nothing). Community is display-only here (claimed via the world prompt, Task 6).

- [ ] **Step 1: Author the readout label in Studio (Edit mode)**

Clone the styled Header description label so the readout matches the shop font. `execute_luau` (Edit):

```lua
local header = game.StarterGui.InGameUI.ShopMenu.Header
local srcLabel = header:FindFirstChild("DescriptionText")
assert(srcLabel and srcLabel:IsA("TextLabel"), "Header.DescriptionText TextLabel missing — re-inspect")
if not header:FindFirstChild("MultiplierText") then
	local copy = srcLabel:Clone()
	copy.Name = "MultiplierText"
	copy.LayoutOrder = (srcLabel.LayoutOrder or 0) + 1
	copy.Text = "Money ×1"
	copy.Parent = header
end
return header.MultiplierText:GetFullName()
```
Expected: returns `...ShopMenu.Header.MultiplierText`. If `Header` uses absolute positioning (no layout), reposition `MultiplierText` in Studio so it's visible under the title. Report what was created.

- [ ] **Step 2: Create `BoostShopController.ts`**

Create `src/client/behaviors/BoostShopController.ts`:

```ts
import { MarketplaceService, Players } from "@rbxts/services";
import { SAFETY_PASS } from "shared/ShopBalance";
import { nextMoneyTier } from "shared/ShopConfig";
import { InformationText } from "client/ui/InformationText";

// Shop "boosts" UI — read-only multiplier readout + two Robux upsell buttons.
// Pure display from replicated attributes (MultRebirth / InCommunity /
// MoneyTierMult / MoneyMult); the buttons prompt a game-pass purchase. A pass
// whose id is 0 is INERT: the button shows a "soon" state and does nothing.
// Community is claimed in-world via the CommunityJoinPart prompt, not here.

const player = Players.LocalPlayer;
const SOON_COLOR = new Color3(1, 0.85, 0.4);

function num(attr: string, fallback: number): number {
	return (player.GetAttribute(attr) as number | undefined) ?? fallback;
}

// "×6", "×3.5" — trim trailing zeros.
function fmtMult(value: number): string {
	const hundredths = math.floor(value * 100 + 1e-7);
	const trimmed = hundredths % 100 === 0 ? tostring(hundredths / 100) : string.format("%.2f", hundredths / 100);
	return `×${trimmed}`;
}

// Resolves RobuxButton/GainQuantityText if present (label of the gained boost).
function gainLabel(robux: Instance): TextLabel | undefined {
	const found = robux.FindFirstChild("GainQuantityText");
	return found && found.IsA("TextLabel") ? found : undefined;
}

// Wires a RobuxButton to prompt `gamePassId`; inert (with a "soon" gain label)
// when the id is 0. `gainText` is the boost it grants (e.g. "×4", "+20% safety").
function bindRobux(robux: TextButton, gamePassId: number, gainText: string): void {
	const label = gainLabel(robux);
	if (label) {
		label.Text = gamePassId > 0 ? gainText : "Bientôt";
		if (gamePassId <= 0) label.TextColor3 = SOON_COLOR;
	}
	robux.Activated.Connect(() => {
		if (gamePassId <= 0) {
			InformationText.show("Bientôt disponible", SOON_COLOR);
			return;
		}
		MarketplaceService.PromptGamePassPurchase(player, gamePassId);
	});
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const shop = inGameUI.WaitForChild("ShopMenu");
	const body = shop.WaitForChild("Body");

	const readout = shop.WaitForChild("Header").WaitForChild("MultiplierText") as TextLabel;

	const moneyRobux = body
		.WaitForChild("AButtonMoney")
		.WaitForChild("ButtonsLayout")
		.WaitForChild("RobuxButton") as TextButton;
	const safetyRobux = body
		.WaitForChild("DSafety")
		.WaitForChild("ButtonsLayout")
		.WaitForChild("RobuxButton") as TextButton;

	// Money-tier upsell: show the NEXT tier above what the player owns.
	const tierMult = num("MoneyTierMult", 1);
	const next = nextMoneyTier(tierMult);
	bindRobux(moneyRobux, next ? next.gamePassId : 0, next ? fmtMult(next.mult) : "MAX");

	// Safety pass: flat +20% (the pass id; inert at 0).
	bindRobux(safetyRobux, SAFETY_PASS.gamePassId, "+20% safety");

	function refresh(): void {
		const rebirth = num("MultRebirth", 1);
		const tier = num("MoneyTierMult", 1);
		const inCommunity = player.GetAttribute("InCommunity") === true;
		const total = num("MoneyMult", 1);
		const community = inCommunity ? "×2" : "×1";
		readout.Text = `Money ${fmtMult(total)}  (Rebirth ${fmtMult(rebirth)} · Communauté ${community} · Palier ${fmtMult(tier)})`;
	}

	player.GetAttributeChangedSignal("MoneyMult").Connect(refresh);
	player.GetAttributeChangedSignal("MultRebirth").Connect(refresh);
	player.GetAttributeChangedSignal("MoneyTierMult").Connect(refresh);
	player.GetAttributeChangedSignal("InCommunity").Connect(refresh);
	refresh();
}
```

- [ ] **Step 3: Init the controller in `main.client.ts`**

In `src/client/main.client.ts`, add the import next to the other behavior imports:

```ts
import { init as initBoostShop } from "./behaviors/BoostShopController";
```

And call it alongside the other shop init (after the existing `ShopItemsController` init call):

```ts
initBoostShop();
```

> If `main.client.ts` imports/initialises behaviors under different local names, match the file's existing style (find where `ShopItemsController`'s `init` is called and add `initBoostShop()` right after it).

- [ ] **Step 4: Build**

Run: `npm run build`
Expected: completes with no type errors (exit 0).

- [ ] **Step 5: Playtest (readout + inert buttons)**

Studio Play mode:
1. Open the shop → `MultiplierText` reads e.g. `Money ×1 (Rebirth ×1 · Communauté ×1 · Palier ×1)` (or ×2 community if you're in the group).
2. The `AButtonMoney` and `DSafety` Robux buttons show "Bientôt" (ids are 0); clicking flashes "Bientôt disponible" and does nothing.
3. Drive the readout live:

```lua
local p = game:GetService("Players"):GetPlayers()[1]
p:SetAttribute("MultRebirth", 2); p:SetAttribute("MoneyTierMult", 4); p:SetAttribute("InCommunity", true)
local Prog = require(game.ServerScriptService.TS.services.PlayerProgressionService).PlayerProgressionService
Prog:recompute(p)
```
The readout updates to `Money ×6 (Rebirth ×2 · Communauté ×2 · Palier ×4)`.

- [ ] **Step 6: Commit**

```bash
git add src/client/behaviors/BoostShopController.ts src/client/main.client.ts out/client/behaviors/BoostShopController.luau out/client/main.client.luau
git commit -m "feat(shop): readout multiplicateur + boutons safety/palier (inertes si id 0)"
```

---

## Task 8: Update ARCHITECTURE.md

**Files:**
- Modify: `ARCHITECTURE.md`

- [ ] **Step 1: Update the relevant sections**

Edit so the docs match the code:

- **§5 (boot order):** insert `BoostService` between `PlayerProgressionService` and `ShopService` — "resolve group + game-pass ownership into input attributes, then recompute; needs Progression's `recompute`, runs before RoomService."
- **§6.3 (game loop):** payout now reads `EffectiveBaseCash` and is `floor(EffectiveBaseCash × currentMultiplier)` on wins / `floor(EffectiveBaseCash × LOOSE_WIN_MULTIPLIER × currentMultiplier)` on death — **no `multRebirth`** (it's folded into `EffectiveBaseCash`). Note safety is now `0..0.70` (shop 0.50 + pass 0.20).
- **§6.4 (end game):** `EndGameStartEvent` payload is `(baseCash=EffectiveBaseCash, multiplier, lossMultiplier)` — `multRebirth` removed; the client animation no longer has a gold rebirth phase.
- **§6.6 (persistence):** add the derived attributes `MoneyMult`, `EffectiveBaseCash` (re-derived by `PlayerProgressionService.deriveValues`/`recompute`) and that `AdditionalSecurity` now includes the safety pass; document `BoostService` writing the input attributes `InCommunity`/`MoneyTierMult`/`HasSafetyPass` from group + game-pass ownership (live per session, **not persisted**, no migration). Note `MoneyMult` is the **additive** total `1 + Σ(mᵢ−1)`.
- **§6.8 (shop):** add the multiplier readout (`ShopMenu/Header/MultiplierText`) + the two wired `RobuxButton`s (money tier upsell on `AButtonMoney`, safety pass on `DSafety`), driven by `BoostShopController`; id 0 = inert.
- **§6.1 (rooms):** the room billboard now mirrors `EffectiveBaseCash` (not raw `BaseCash`); add the optional `CommunityJoinPart` (ProximityPrompt) sibling of `ButtonModel`, wired in `RoomService` to `BoostService.refreshCommunity`.
- **§7 (event catalog):** update `EndGameStartEvent` to drop the `multRebirth` arg. (No new events.)
- **§8 (tuning constants):** add `COMMUNITY` (group 963505568, ×2), `MONEY_TIERS` (×2…×1024, highest owned wins), `SAFETY_PASS` (+0.20), `SAFETY_TOTAL_CAP` (0.70), all in `shared/ShopBalance.ts`.

- [ ] **Step 2: Self-check the doc**

Re-read each edited section; confirm no stale "payout × MultRebirth" wording remains and the boot order / persistence / event descriptions match Tasks 1–7.

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs(architecture): money multipliers sur base cash (BoostService, additif)"
```

---

## Done — acceptance criteria (from the spec §15)

1. Billboard + HUD show `EffectiveBaseCash = floor(BaseCash × MoneyMult)`, `MoneyMult` additive, live on factor change (Tasks 3, 6). ✔
2. Payout = `floor(EffectiveBaseCash × currentMultiplier)` (win) / `× LOOSE_WIN_MULTIPLIER` (death); no `multRebirth` (Task 5). ✔
3. Community: group 963505568 ⇒ `+1` bonus, server-verified, re-checked via `CommunityJoinPart` prompt (Tasks 4, 6). ✔
4. Money tier: `MoneyTierMult` = highest owned tier; id 0 inert (Task 4). ✔
5. Safety pass: `AdditionalSecurity = min(shopSafety + 0.20, 0.70)` (Tasks 1–3). ✔
6. End-game animation starts from `EffectiveBaseCash`, no gold rebirth phase, equals credited amount (Task 5). ✔
7. `EndGameStartEvent` drops `multRebirth`; no new RemoteEvent (Tasks 5, 6). ✔
8. No DataStore migration; boosts resolved per session (Task 4). ✔
9. Shop readout (each factor + total) + inert safety/tier buttons (Task 7). ✔
10. `ARCHITECTURE.md` updated (Task 8). ✔
