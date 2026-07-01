import { ShopStat } from "./ShopConfig";

// ── Progression developer products ─────────────────────────────────────────────
// Robux dev products sold on the shop RobuxButtons (InGameUI/ShopMenu/Body/*).
// Unlike the money packs (shared/MoneyProducts.ts) these grant progression LEVELS,
// not Money. Single source of truth shared by both sides:
//   • client (ShopItemsController) wires each frame's RobuxButton to prompt the
//     product matching its stat, and renders the gain label + Robux price.
//   • server (MoneyProductService.ProcessReceipt) adds `levels` to `stat` for the
//     purchased productId.
// One product can back several buttons: BaseCash +10 sits on BOTH the +1
// (AButtonMoney) and +5 (BX5ButtonMoney) frames — both resolve via their shared
// `stat`. The Robux price is configured per product on the Roblox dashboard.

export type LevelProduct = {
	readonly productId: number;
	readonly stat: ShopStat;
	readonly levels: number;
};

export const LEVEL_PRODUCTS: ReadonlyArray<LevelProduct> = [
	{ productId: 3605483805, stat: "BaseCash", levels: 10 },
	{ productId: 3605483849, stat: "RocketSpeed", levels: 10 },
	{ productId: 3605484029, stat: "Resistance", levels: 1 },
];

// Level grant for a purchased productId, or undefined if it isn't one of ours.
// Server-side lookup (ProcessReceipt).
export function levelGrantForProduct(productId: number): LevelProduct | undefined {
	for (const product of LEVEL_PRODUCTS) {
		if (product.productId === productId) return product;
	}
	return undefined;
}

// The level product backing a given stat, or undefined if none. Client-side
// lookup — every shop frame resolves its RobuxButton product through its stat.
export function levelProductForStat(stat: ShopStat): LevelProduct | undefined {
	for (const product of LEVEL_PRODUCTS) {
		if (product.stat === stat) return product;
	}
	return undefined;
}
