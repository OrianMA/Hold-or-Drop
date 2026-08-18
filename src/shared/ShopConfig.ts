import { FormatNumber } from "./NumberFormat";
import { resistanceRiskParams } from "./ResistanceCurve";
import {
	BASE_CASH,
	COMMUNITY,
	MONEY_TIERS,
	REBIRTH,
	RESISTANCE,
	RESISTANCE_PASS,
	ROCKET_SPEED,
} from "./ShopBalance";

// ── Shop — structure + formulas ───────────────────────────────────────────────
// Pure logic, no side effects. Imported by both the server (purchase authority)
// and the client (display). Levels are the persisted source of truth
// (PlayerProgressionService); the effective values and prices are *derived* from
// the level here. All tunable numbers live in shared/ShopBalance.ts — edit there
// to rebalance.

// A stat is one upgradeable progression value. A shop button targets exactly one
// stat (one button per stat for now — the BaseCash +5 button is disabled).
export type ShopStat = "BaseCash" | "RocketSpeed" | "Resistance";

// One per shop button under InGameUI/ShopMenu/Body.
export type ShopItemId = "BaseCash" | "RocketSpeed" | "Resistance";

// Contexte passé au rendu d'une stat. `moneyMult` permet à BaseCash d'afficher le gain
// EFFECTIF (multiplicateur de rebirth et boosts inclus) plutôt que la valeur brute :
// après quelques rebirths, "1K → 1.2K" devient "512K → 614K".
export interface DisplayContext {
	readonly moneyMult: number;
}

export interface StatConfig {
	// Attribute the rest of the game reads (unchanged names — game loop, billboard).
	readonly valueAttribute: string;
	// Attribute holding the persisted level (the source of truth).
	readonly levelAttribute: string;
	readonly startPrice: number; // price of the very first level (level 0 → 1)
	readonly priceGrowth: number; // multiplicateur de prix par niveau (propre à la stat)
	// Prix imposés des premiers niveaux (index = niveau de départ) ; au-delà, la formule
	// reprend. Sert l'onboarding — voir ShopBalance.ROCKET_SPEED.firstLevelPrices.
	readonly firstLevelPrices?: readonly number[];
	readonly maxLevel?: number; // inclusive cap; undefined = uncapped
	// Effective value at a given level. Property (not method) so it matches the
	// arrow-function assignments below — roblox-ts separates `.` and `:` calls.
	readonly valueFor: (level: number) => number;
	// Rendu lisible par un joueur de la valeur de la stat (pas le nombre brut).
	readonly display: (value: number, ctx: DisplayContext) => string;
}

export const STATS: { readonly [K in ShopStat]: StatConfig } = {
	BaseCash: {
		valueAttribute: "BaseCash",
		levelAttribute: "BaseCashLevel",
		startPrice: BASE_CASH.startPrice,
		priceGrowth: BASE_CASH.priceGrowth,
		valueFor: (level) => math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ** level),
		// Gain effectif = ce que le joueur encaisse vraiment (EffectiveBaseCash).
		display: (value, ctx) => `${FormatNumber(math.floor(value * ctx.moneyMult))}$`,
	},
	RocketSpeed: {
		valueAttribute: "RocketSpeed",
		levelAttribute: "RocketSpeedLevel",
		startPrice: ROCKET_SPEED.startPrice,
		priceGrowth: ROCKET_SPEED.priceGrowth,
		firstLevelPrices: ROCKET_SPEED.firstLevelPrices,
		valueFor: (level) => ROCKET_SPEED.baseValue + level,
		// Vitesse brute seule (le multiplicateur entre parenthèses a été retiré).
		display: (value) => `${value}`,
	},
	Resistance: {
		valueAttribute: "Resistance",
		levelAttribute: "ResistanceLevel",
		startPrice: RESISTANCE.startPrice,
		priceGrowth: RESISTANCE.priceGrowth,
		maxLevel: RESISTANCE.maxLevel,
		valueFor: (level) => level,
		// Secondes de vol garanties — la seule formulation compréhensible de cette stat.
		display: (value) => `${string.format("%.1f", resistanceRiskParams(value).safeWindow)}s`,
	},
};

export interface ShopItem {
	readonly id: ShopItemId;
	readonly stat: ShopStat;
	readonly quantity: number; // levels granted per purchase
	readonly frameName: string; // Studio frame under ShopMenu/Body
	readonly title: string; // BoostTitleText
}

export const ITEMS: { readonly [K in ShopItemId]: ShopItem } = {
	BaseCash: { id: "BaseCash", stat: "BaseCash", quantity: 1, frameName: "BButtonMoney", title: "Button money" },
	RocketSpeed: {
		id: "RocketSpeed",
		stat: "RocketSpeed",
		quantity: 1,
		frameName: "ARocketSpeed",
		title: "Rocket speed",
	},
	Resistance: { id: "Resistance", stat: "Resistance", quantity: 1, frameName: "DSafety", title: "Vol garanti" },
};

// Iteration order for the client (matches the A/B/D frame ordering).
export const ITEM_ORDER: readonly ShopItemId[] = ["RocketSpeed", "BaseCash", "Resistance"];

// Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
// serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix, et peut
// imposer les prix de ses premiers niveaux (firstLevelPrices).
export function priceForLevel(stat: ShopStat, level: number): number {
	const cfg = STATS[stat];
	const override = cfg.firstLevelPrices?.[level];
	if (override !== undefined) return override;
	return math.floor(cfg.startPrice * cfg.priceGrowth ** level);
}

// Total price to buy a whole item from `fromLevel` (strict sum of each level —
// no bulk discount). For a +1 item this is just priceForLevel.
export function priceForItem(item: ShopItem, fromLevel: number): number {
	let total = 0;
	for (let i = 0; i < item.quantity; i++) {
		total += priceForLevel(item.stat, fromLevel + i);
	}
	return total;
}

// True when the stat is at (or above) its cap and cannot be upgraded further.
export function isAtCap(stat: ShopStat, level: number): boolean {
	const max = STATS[stat].maxLevel;
	return max !== undefined && level >= max;
}

// ── Rebirth pricing & reward (pure, shared client/server) ─────────────────────

// Cash threshold required to perform rebirth number R+1 (R = rebirths already done).
export function rebirthCost(rebirths: number): number {
	const r = math.max(0, math.floor(rebirths));
	const override = REBIRTH.firstCosts[r];
	if (override !== undefined) return override;
	return math.floor(REBIRTH.baseCost * REBIRTH.costGrowth ** r);
}

// Multiplicateur d'argent permanent après `rebirths` rebirths. Géométrique : chaque
// rebirth multiplie le précédent par REBIRTH.multGrowth.
export function rebirthMult(rebirths: number): number {
	const r = math.max(0, math.floor(rebirths));
	return REBIRTH.multGrowth ** r;
}

// ── Multiplicateurs d'argent — rebirth multiplicatif, boosts additifs ────────────
// Le rebirth MULTIPLIE ; la communauté et le palier de game-pass s'additionnent entre
// eux dans un facteur de boost commun :
//   moneyMult = MultRebirth × (1 + (communauté − 1) + (palier − 1))
// Conséquence voulue : un pass ×2 reste ×2 quel que soit le niveau de rebirth. Avec un
// modèle purement additif, un MultRebirth de 4096 écraserait les paliers MONEY_TIERS
// (un pass ×2 n'ajouterait plus que +1 sur 4096) et les rendrait invendables.
export function moneyMult(multRebirth: number, moneyTierMult: number, inCommunity: boolean): number {
	const communityBonus = inCommunity ? COMMUNITY.mult - 1 : 0;
	const tierBonus = moneyTierMult - 1;
	return multRebirth * (1 + communityBonus + tierBonus);
}

// Effective resistance used by the risk loop: shop Resistance + the resistance
// game pass (flat bonus levels), capped at the max level.
export function effectiveResistance(shopResistance: number, hasResistancePass: boolean): number {
	const total = shopResistance + (hasResistancePass ? RESISTANCE_PASS.addLevels : 0);
	return math.min(total, RESISTANCE.maxLevel);
}

// The next money tier strictly above `currentMult` (for the shop upsell), or
// undefined if already at the top. Tiers are a ladder — the highest owned wins.
export function nextMoneyTier(currentMult: number): { mult: number; gamePassId: number } | undefined {
	for (const tier of MONEY_TIERS) {
		if (tier.mult > currentMult) return tier;
	}
	return undefined;
}
