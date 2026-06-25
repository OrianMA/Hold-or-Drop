-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local MONEY_PRODUCTS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MoneyProducts").MONEY_PRODUCTS
-- Opens / closes the "buy money with Robux" popup (InGameUI/ShopMoneyBuy) and
-- wires its 9 product buttons to MarketplaceService developer-product prompts.
--   • Opened by the HUD's MoneyParent/PlusButton/TextButton.
--   • Closed by ShopMoneyBuy/Header/CloseButtonFrame/CloseButton.
--   • Body/MoneyElement{n}/Button prompts MONEY_PRODUCTS[n-1].productId; the server
--     (MoneyProductService) credits the money on a successful receipt.
-- Opening hides the persistent HUD (mirrors ShopBehavior); closing restores it.
-- Purely client-side — the purchase + grant are validated server-side.
local SHOP_MONEY_BUY = "ShopMoneyBuy"
local function init()
	local player = Players.LocalPlayer
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local popup = inGameUI:WaitForChild(SHOP_MONEY_BUY)
	local closeButton = popup:WaitForChild("Header"):WaitForChild("CloseButtonFrame"):WaitForChild("CloseButton")
	local body = popup:WaitForChild("Body")
	-- The opener lives inside the HUD itself.
	local openButton = inGameUI:WaitForChild("HUD"):WaitForChild("MoneyParent"):WaitForChild("PlusButton"):WaitForChild("TextButton")
	popup.Visible = false
	local open = function()
		popup.Visible = true
		InGameUIController:disable()
	end
	local close = function()
		popup.Visible = false
		InGameUIController:enable()
	end
	openButton.Activated:Connect(open)
	closeButton.Activated:Connect(close)
	-- Wire each product button to prompt its developer product. Order matches the
	-- GUI: MoneyElement{n} ↔ MONEY_PRODUCTS[n-1].
	-- ▼ ReadonlyArray.forEach ▼
	local _callback = function(product, index)
		local button = body:WaitForChild(`MoneyElement{index + 1}`):WaitForChild("Button")
		button.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(player, product.productId)
		end)
	end
	for _k, _v in MONEY_PRODUCTS do
		_callback(_v, _k - 1, MONEY_PRODUCTS)
	end
	-- ▲ ReadonlyArray.forEach ▲
end
return {
	init = init,
}
