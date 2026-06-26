import { FormatNumber } from "./NumberFormat";
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

// ── Shop — structure + formulas ───────────────────────────────────────────────
// Pure logic, no side effects. Imported by both the server (purchase authority)
// and the client (display). Levels are the persisted source of truth
// (PlayerProgressionService); the effective values and prices are *derived* from
// the level here. All tunable numbers live in shared/ShopBalance.ts — edit there
// to rebalance.

// A stat is one upgradeable progression value. Multiple shop buttons may target
// the same stat (BaseCash is sold both as +1 and +5).
export type ShopStat = "BaseCash" | "Multiplier" | "Safety";

// One per shop button under InGameUI/ShopMenu/Body.
export type ShopItemId = "BaseCash" | "BaseCashX5" | "Multiplier" | "Safety";

export interface StatConfig {
	// Attribute the rest of the game reads (unchanged names — game loop, billboard).
	readonly valueAttribute: string;
	// Attribute holding the persisted level (the source of truth).
	readonly levelAttribute: string;
	readonly startPrice: number; // price of the very first level (level 0 → 1)
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
		valueFor: (level) => math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ** level),
		display: (value) => FormatNumber(value),
	},
	Multiplier: {
		valueAttribute: "Multiplier",
		levelAttribute: "MultiplierLevel",
		startPrice: MULTIPLIER.startPrice,
		valueFor: (level) => MULTIPLIER.baseValue * MULTIPLIER.valueGrowth ** level,
		// Small values keep decimals (0.1, 2.65); large values abbreviate.
		display: (value) => (value < 1000 ? trimDecimals(value) : FormatNumber(value)),
	},
	Safety: {
		valueAttribute: "AdditionalSecurity",
		levelAttribute: "SafetyLevel",
		startPrice: SAFETY.startPrice,
		maxLevel: SAFETY.maxLevel,
		valueFor: (level) => math.min(level * SAFETY.perLevel, SAFETY.perLevel * SAFETY.maxLevel),
		display: (value) => string.format("%d%%", math.round(value * 100)),
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
	BaseCash: { id: "BaseCash", stat: "BaseCash", quantity: 1, frameName: "AButtonMoney", title: "Button money" },
	BaseCashX5: {
		id: "BaseCashX5",
		stat: "BaseCash",
		quantity: 5,
		frameName: "BX5ButtonMoney",
		title: "+5 lvl Button money",
	},
	Multiplier: {
		id: "Multiplier",
		stat: "Multiplier",
		quantity: 1,
		frameName: "CMultiplier",
		title: "Multiplier speed",
	},
	Safety: { id: "Safety", stat: "Safety", quantity: 1, frameName: "DSafety", title: "Additionnal safety" },
};

// Iteration order for the client (matches the A/B/C/D frame ordering).
export const ITEM_ORDER: readonly ShopItemId[] = ["BaseCash", "BaseCashX5", "Multiplier", "Safety"];

// Price to go from `level` → `level + 1` for a stat. Deterministic integer so
// client and server always agree.
export function priceForLevel(stat: ShopStat, level: number): number {
	return math.floor(STATS[stat].startPrice * PRICE_GROWTH ** level);
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
