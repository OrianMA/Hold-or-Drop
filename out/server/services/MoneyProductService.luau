-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local amountForProduct = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MoneyProducts").amountForProduct
local levelGrantForProduct = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "LevelProducts").levelGrantForProduct
local STATS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").STATS
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
-- Authoritative handler for ALL developer products. Owns the game's single
-- MarketplaceService.ProcessReceipt callback. Two product families route through
-- here:
--   • money packs (shared/MoneyProducts.ts)   → credit Money       (ShopMoneyBuy popup)
--   • progression products (shared/LevelProducts.ts) → add stat LEVELS (shop RobuxButtons)
--
-- On a receipt we apply the matching grant and return PurchaseGranted. We return
-- NotProcessedYet (Roblox retries later) when the buyer isn't in-game or their data
-- is still loading (relevant attribute unset) — so a grant is never lost, nor
-- written before/over a fresh load. Each grant is a synchronous attribute write
-- immediately followed by the return, so there is no double-grant window and no
-- DataStore receipt log is needed.
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
	if amount ~= nil then
		PlayerDataService:add(player, "Money", amount)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local grant = levelGrantForProduct(receiptInfo.ProductId)
	if grant ~= nil then
		-- Progression levels load after Money — retry until the stat's level attribute
		-- exists so addLevel doesn't run before/over a fresh progression load.
		if player:GetAttribute(STATS[grant.stat].levelAttribute) == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- addLevel clamps to the stat's cap (e.g. Safety) — a max-level buy is a no-op
		-- gain but still granted (the client prevents prompting at the cap).
		PlayerProgressionService:addLevel(player, grant.stat, grant.levels)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn(`MoneyProductService: unknown developer product {receiptInfo.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
local MoneyProductService = {
	init = function(self)
		MarketplaceService.ProcessReceipt = processReceipt
	end,
}
return {
	MoneyProductService = MoneyProductService,
}
