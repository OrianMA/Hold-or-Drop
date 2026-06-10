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
//   value = baseValue * valueGrowth ^ level   (L0=100, L10≈259, L50≈11.7K)
//   price = startPrice * PRICE_GROWTH ^ level  (L0→1 = 25)
export const BASE_CASH = {
	baseValue: 100,
	valueGrowth: 1.8,
	startPrice: 25,
};

// Multiplier — per-second growth during a hold. Uncapped.
//   value = baseValue * valueGrowth ^ level   (L0=0.1, L10≈0.26, L50≈11.7)
//   price = startPrice * PRICE_GROWTH ^ level  (L0→1 = 100)
export const MULTIPLIER = {
	baseValue: 0.1,
	valueGrowth: 1.3,
	startPrice: 100,
};

// Safety — risk reduction, capped. The cap value is perLevel * maxLevel.
//   value = min(level * perLevel, perLevel * maxLevel)   (L10 = 50%)
//   price = startPrice * PRICE_GROWTH ^ level             (L0→1 = 2000)
export const SAFETY = {
	perLevel: 0.05, // +5% risk reduction per level
	maxLevel: 10, // cap → 10 × 5% = 50%
	startPrice: 2000,
};
