-- Compiled with roblox-ts v3.0.0
-- ── Progression developer products ─────────────────────────────────────────────
-- Robux dev products sold on the shop RobuxButtons (InGameUI/ShopMenu/Body/*).
-- Unlike the money packs (shared/MoneyProducts.ts) these grant progression LEVELS,
-- not Money. Single source of truth shared by both sides:
--   • client (ShopItemsController) wires each frame's RobuxButton to prompt the
--     product matching its stat, and renders the gain label + Robux price.
--   • server (MoneyProductService.ProcessReceipt) adds `levels` to `stat` for the
--     purchased productId.
-- One product can back several buttons: BaseCash +10 sits on BOTH the +1
-- (AButtonMoney) and +5 (BX5ButtonMoney) frames — both resolve via their shared
-- `stat`. The Robux price is configured per product on the Roblox dashboard.
local LEVEL_PRODUCTS = { {
	productId = 3605483805,
	stat = "BaseCash",
	levels = 10,
}, {
	productId = 3605483849,
	stat = "RocketSpeed",
	levels = 10,
}, {
	productId = 3605484029,
	stat = "Safety",
	levels = 1,
} }
-- Level grant for a purchased productId, or undefined if it isn't one of ours.
-- Server-side lookup (ProcessReceipt).
local function levelGrantForProduct(productId)
	for _, product in LEVEL_PRODUCTS do
		if product.productId == productId then
			return product
		end
	end
	return nil
end
-- The level product backing a given stat, or undefined if none. Client-side
-- lookup — every shop frame resolves its RobuxButton product through its stat.
local function levelProductForStat(stat)
	for _, product in LEVEL_PRODUCTS do
		if product.stat == stat then
			return product
		end
	end
	return nil
end
return {
	levelGrantForProduct = levelGrantForProduct,
	levelProductForStat = levelProductForStat,
	LEVEL_PRODUCTS = LEVEL_PRODUCTS,
}
