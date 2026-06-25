-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local amountForProduct = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MoneyProducts").amountForProduct
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
-- Authoritative handler for the Robux "buy money" developer products (the 9 packs
-- in the ShopMoneyBuy popup). Owns the game's single MarketplaceService.ProcessReceipt
-- callback — route any future developer products through here.
--
-- On a receipt we credit the mapped amount to the buyer's Money and return
-- PurchaseGranted. We return NotProcessedYet (Roblox retries later) when the buyer
-- isn't in-game or their data is still loading (Money attribute unset) — so a grant
-- is never lost, nor written before/over a fresh load. The grant is a synchronous
-- attribute write immediately followed by the return, so there is no double-grant
-- window and no DataStore receipt log is needed.
local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Data still loading (PlayerDataService sets Money after its async load) — retry
	-- so the grant isn't overwritten by the load.
	if player:GetAttribute("Money") == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local amount = amountForProduct(receiptInfo.ProductId)
	if amount == nil then
		warn(`MoneyProductService: unknown developer product {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	PlayerDataService:add(player, "Money", amount)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
local MoneyProductService = {
	init = function(self)
		MarketplaceService.ProcessReceipt = processReceipt
	end,
}
return {
	MoneyProductService = MoneyProductService,
}
