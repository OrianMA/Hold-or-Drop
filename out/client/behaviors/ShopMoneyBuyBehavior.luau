-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local MONEY_PRODUCTS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MoneyProducts").MONEY_PRODUCTS
-- Opens / closes the "buy money with Robux" popup (InGameUI/ShopMoneyBuy) and
-- wires its 9 product buttons to MarketplaceService developer-product prompts.
--   • Opened by MoneyParent/PlusButton/TextButton — celui du HUD, ET celui du
--     miroir InGameUI/MoneyParent affiché pendant le shop (§6.8) quand il existe :
--     les deux "+" sont le même bouton pour le joueur, il serait mort dans le miroir
--     s'il n'était pas branché lui aussi.
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
	-- L'ouvreur du HUD existe toujours : lui seul est attendu (WaitForChild).
	local openButton = inGameUI:WaitForChild("HUD"):WaitForChild("MoneyParent"):WaitForChild("PlusButton"):WaitForChild("TextButton")
	-- Le miroir affiché pendant le shop est OPTIONNEL (§6.8) : on le résout en
	-- FindFirstChild, jamais en WaitForChild — les init clients sont séquentiels, un
	-- yield infini ici tuerait tous les comportements enregistrés après celui-ci.
	local _mirrorButton = inGameUI:FindFirstChild("MoneyParent")
	if _mirrorButton ~= nil then
		_mirrorButton = _mirrorButton:FindFirstChild("PlusButton")
		if _mirrorButton ~= nil then
			_mirrorButton = _mirrorButton:FindFirstChild("TextButton")
		end
	end
	local mirrorButton = _mirrorButton
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
	local _result = mirrorButton
	if _result ~= nil then
		_result = _result:IsA("GuiButton")
	end
	if _result then
		mirrorButton.Activated:Connect(open)
	end
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
