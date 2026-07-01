// ── Shop balancing ────────────────────────────────────────────────────────────
// THE place to retune the shop economy. Only numbers live here — the formulas
// and wiring are in shared/ShopConfig.ts. Because progression stores LEVELS (not
// values), editing anything below instantly rebalances every player with no save
// migration.
//
// Two curve shapes (defined in ShopConfig, fed by the numbers here):
//   • exponential value : baseValue * valueGrowth ^ level   (BaseCash)
//   • linear value      : baseValue + level                 (RocketSpeed / Resistance)
//   • price (all stats) : startPrice * PRICE_GROWTH ^ level

// Price multiplier applied per level for every stat. Higher = steeper grind wall.
//   1.5 → each level costs +50% of the previous.
export const PRICE_GROWTH = 1.5;

// BaseCash — the button's base payout. Uncapped.
//   value = baseValue * valueGrowth ^ level   (L0=100, L10≈619, L20≈3.8K)
//   price = startPrice * PRICE_GROWTH ^ level  (L0→1 = 25)
//   Invariant: valueGrowth < PRICE_GROWTH (1.20 < 1.5) so price outpaces value.
export const BASE_CASH = {
	baseValue: 100,
	valueGrowth: 1.2,
	startPrice: 25,
};

// Rocket Speed — drives BOTH the rocket's ascent speed and how fast the payout
// multiplier grows (the multiplier tracks the rocket's live velocity, so a faster
// rocket = a faster-climbing multiplier). Integer, +1 per level, uncapped.
//   value = baseValue + level   (L0=1 → rocket crawls, multiplier barely moves;
//                                each level is a full unit → noticeably faster at once)
//   actual rocket accel/max = value × the per-unit constants in RocketGameConfig.
//   price = startPrice * PRICE_GROWTH ^ level  (L0→1 = 100)
export const ROCKET_SPEED = {
	baseValue: 1,
	startPrice: 100,
};

// Resistance — explosion-risk reduction, 0..100. Bought +1 per level like Rocket
// Speed (plain integer, +1 each purchase). The number itself is NOT a percentage:
// it feeds a curve applied in the risk loop (ButtonInGameModule.resistanceRiskParams).
// The curve is front-loaded — the FIRST levels hugely raise average survival, the
// LAST levels barely change it but push out the guaranteed-safe window toward ~15s.
//   value = level (plain 0..100)
//   price = startPrice * PRICE_GROWTH ^ level   (L0→1 = 500)
//   startPrice 500: Resistance resets each rebirth cycle, so early levels (the ones
//   that matter most) must be reachable within a single early cycle.
export const RESISTANCE = {
	maxLevel: 100,
	startPrice: 500,
};

// ── Rebirth ──────────────────────────────────────────────────────────────────
// Reset everything (cash + the 3 stat levels) for a permanent money multiplier.
//   cost(R) = floor(baseCost * costGrowth ^ R)   (R = rebirths already done)
//   mult(R) = multTable[R] for R inside the table, then linear queue of multTail.
// multTable index 0 = no rebirth (×1). R1→×2, R2→×3, R3→×3.5, … R7→×5.
export const REBIRTH = {
	baseCost: 2500,
	costGrowth: 2.4,
	multTable: [1, 2, 3, 3.5, 4, 4.5, 4.75, 5],
	multTail: 0.25,
};

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
	{ mult: 2, gamePassId: 1891624935 },
	{ mult: 4, gamePassId: 1893448867 },
	{ mult: 8, gamePassId: 1889872933 },
	{ mult: 16, gamePassId: 1893904460 },
	{ mult: 32, gamePassId: 1889866920 },
	{ mult: 64, gamePassId: 1891528981 },
	{ mult: 128, gamePassId: 1890406985 },
	{ mult: 256, gamePassId: 1890424956 },
	{ mult: 512, gamePassId: 1893634520 },
	{ mult: 1024, gamePassId: 1890592911 },
];

// Resistance game pass — flat bonus resistance LEVELS added on top of the shop
// Resistance (id 0 = inert until authored on the dashboard). Capped at maxLevel.
export const RESISTANCE_PASS = { addLevels: 20, gamePassId: 0 };
