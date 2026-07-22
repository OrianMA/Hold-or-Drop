import { FormatNumber } from "./NumberFormat";
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

export interface StatConfig {
	// Attribute the rest of the game reads (unchanged names — game loop, billboard).
	readonly valueAttribute: string;
	// Attribute holding the persisted level (the source of truth).
	readonly levelAttribute: string;
	readonly startPrice: number; // price of the very first level (level 0 → 1)
	readonly priceGrowth: number; // multiplicateur de prix par niveau (propre à la stat)
	readonly maxLevel?: number; // inclusive cap; undefined = uncapped
	// Effective value at a given level. Property (not method) so it matches the
	// arrow-function assignments below — roblox-ts separates `.` and `:` calls.
	readonly valueFor: (level: number) => number;
	// Human-readable rendering of a value (e.g. "50%", "11.7K").
	readonly display: (value: number) => string;
}

// Up to 2 decimals, trailing zeros trimmed: 0.1, 2.65, 11.7. Mirrors the small
// number rendering used by NumberFormat without flooring sub-1 values to "0".
function trimDecimals(value: number): string {
	const hundredths = math.floor(value * 100 + 1e-7);
	if (hundredths % 100 === 0) return tostring(hundredths / 100);
	if (hundredths % 10 === 0) return string.format("%.1f", hundredths / 100);
	return string.format("%.2f", hundredths / 100);
}

export const STATS: { readonly [K in ShopStat]: StatConfig } = {
	BaseCash: {
		valueAttribute: "BaseCash",
		levelAttribute: "BaseCashLevel",
		startPrice: BASE_CASH.startPrice,
		priceGrowth: BASE_CASH.priceGrowth,
		valueFor: (level) => math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ** level),
		display: (value) => FormatNumber(value),
	},
	RocketSpeed: {
		valueAttribute: "RocketSpeed",
		levelAttribute: "RocketSpeedLevel",
		startPrice: ROCKET_SPEED.startPrice,
		priceGrowth: ROCKET_SPEED.priceGrowth,
		valueFor: (level) => ROCKET_SPEED.baseValue + level,
		// Plain integer speed (1, 2, 3…).
		display: (value) => tostring(value),
	},
	Resistance: {
		valueAttribute: "Resistance",
		levelAttribute: "ResistanceLevel",
		startPrice: RESISTANCE.startPrice,
		priceGrowth: RESISTANCE.priceGrowth,
		maxLevel: RESISTANCE.maxLevel,
		// Plain 0..100 level — the risk-curve mapping lives in ButtonInGameModule.
		valueFor: (level) => level,
		// Plain integer (1, 2, 3…) like Rocket Speed.
		display: (value) => tostring(value),
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
	Resistance: { id: "Resistance", stat: "Resistance", quantity: 1, frameName: "DSafety", title: "Resistance" },
};

// Iteration order for the client (matches the A/B/D frame ordering).
export const ITEM_ORDER: readonly ShopItemId[] = ["RocketSpeed", "BaseCash", "Resistance"];

// Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
// serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix.
export function priceForLevel(stat: ShopStat, level: number): number {
	const cfg = STATS[stat];
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
	return math.floor(REBIRTH.baseCost * REBIRTH.costGrowth ** r);
}

// Permanent money multiplier after `rebirths` rebirths. Table for the designed
// early curve, then a constant linear queue (+multTail per extra rebirth).
export function rebirthMult(rebirths: number): number {
	const r = math.max(0, math.floor(rebirths));
	const multTable = REBIRTH.multTable;
	const lastIndex = multTable.size() - 1;
	if (r <= lastIndex) return multTable[r];
	return multTable[lastIndex] + (r - lastIndex) * REBIRTH.multTail;
}

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
