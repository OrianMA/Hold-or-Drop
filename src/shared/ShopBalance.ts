// ── Shop balancing ────────────────────────────────────────────────────────────
// THE place to retune the shop economy. Only numbers live here — the formulas
// and wiring are in shared/ShopConfig.ts. Because progression stores LEVELS (not
// values), editing anything below instantly rebalances every player with no save
// migration.
//
// Two curve shapes (defined in ShopConfig, fed by the numbers here):
//   • exponential value : baseValue * valueGrowth ^ level   (BaseCash, Multiplier)
//   • linear value      : level * perLevel  (capped)         (Safety)
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

// Multiplier — per-second growth during a hold. Uncapped.
//   value = baseValue * valueGrowth ^ level   (L0=0.1, L10≈0.52, L20≈2.7)
//   price = startPrice * PRICE_GROWTH ^ level  (L0→1 = 100)
//   Invariant: valueGrowth < PRICE_GROWTH (1.18 < 1.5).
export const MULTIPLIER = {
	baseValue: 0.1,
	valueGrowth: 1.18,
	startPrice: 100,
};

// Safety — risk reduction, capped. The cap value is perLevel * maxLevel.
//   value = min(level * perLevel, perLevel * maxLevel)   (L10 = 50%)
//   price = startPrice * PRICE_GROWTH ^ level             (L0→1 = 500)
//   startPrice lowered to 500: Safety resets each rebirth cycle, so it must be
//   reachable within a single early cycle.
export const SAFETY = {
	perLevel: 0.05, // +5% risk reduction per level
	maxLevel: 10, // cap → 10 × 5% = 50%
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

// Safety game pass — flat risk reduction added on top of the shop Safety.
export const SAFETY_PASS = { add: 0.2, gamePassId: 0 };

// Cumulative safety cap: shop (0.50) + pass (0.20). Keeps risk floored at ×0.30.
export const SAFETY_TOTAL_CAP = 0.7;
