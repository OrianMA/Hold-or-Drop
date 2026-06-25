// ── Money developer products ───────────────────────────────────────────────────
// The 9 Robux "buy money" packs sold from the ShopMoneyBuy popup. The list is
// ORDERED to match the GUI: index i ↔ Body/MoneyElement{i+1}. Single source of
// truth shared by both sides:
//   • client (ShopMoneyBuyBehavior) wires each MoneyElement's Button to prompt the
//     matching productId.
//   • server (MoneyProductService.ProcessReceipt) credits `amount` Money for the
//     purchased productId.
// `amount` mirrors each element's ValueText label (display only); the Robux price
// is configured per product on the Roblox dashboard, not here.

export type MoneyProduct = {
	readonly productId: number;
	readonly amount: number;
};

export const MONEY_PRODUCTS: ReadonlyArray<MoneyProduct> = [
	{ productId: 3606523199, amount: 250 },
	{ productId: 3606523294, amount: 2000 },
	{ productId: 3606523439, amount: 10000 },
	{ productId: 3606523534, amount: 50000 },
	{ productId: 3606522607, amount: 200000 },
	{ productId: 3606523726, amount: 500000 },
	{ productId: 3606523783, amount: 1000000 },
	{ productId: 3606523840, amount: 10000000 },
	{ productId: 3606523919, amount: 100000000 },
];

// Money granted for a purchased productId, or undefined if it isn't one of ours.
export function amountForProduct(productId: number): number | undefined {
	for (const product of MONEY_PRODUCTS) {
		if (product.productId === productId) return product.amount;
	}
	return undefined;
}
