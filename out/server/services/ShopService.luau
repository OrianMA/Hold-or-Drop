-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local ITEMS = _ShopConfig.ITEMS
local isAtCap = _ShopConfig.isAtCap
local priceForItem = _ShopConfig.priceForItem
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local _AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService")
local AnalyticsService = _AnalyticsService.AnalyticsService
local TxType = _AnalyticsService.TxType
local QuestService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "QuestService").QuestService
local NeonPipeColors = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "NeonPipeColors").NeonPipeColors
-- Authoritative shop purchases. The client pre-checks affordability for instant
-- feedback, but every purchase is fully re-validated here — never trust the
-- client. Cash only; Robux buttons are not wired yet.
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
local function isShopItemId(value)
	local _value = value
	local _condition = type(_value) == "string"
	if _condition then
		_condition = ITEMS[value] ~= nil
	end
	return _condition
end
local function handlePurchase(player, itemId)
	if not isShopItemId(itemId) then
		return nil
	end
	local item = ITEMS[itemId]
	local level = PlayerProgressionService:getLevel(player, item.stat)
	if isAtCap(item.stat, level) then
		Events.InformationTextEvent:FireClient(player, "Niveau maximum atteint", {
			color = DENIED_COLOR,
		})
		return nil
	end
	local price = priceForItem(item, level)
	if PlayerDataService:get(player, "Money") < price then
		Events.InformationTextEvent:FireClient(player, "Pas assez d'argent", {
			color = DENIED_COLOR,
		})
		return nil
	end
	PlayerDataService:add(player, "Money", -price)
	PlayerProgressionService:addLevel(player, item.stat, item.quantity)
	-- Quêtes : "Buy N upgrades" compte les NIVEAUX achetés (un item peut en donner
	-- plusieurs), pas les clics.
	QuestService:report(player, "UpgradesBought", item.quantity)
	-- Analytics: cash Sink (with the resulting balance) + per-item counter + onboarding step 4.
	AnalyticsService:cashSink(player, price, PlayerDataService:get(player, "Money"), TxType.Shop, itemId)
	AnalyticsService:custom(player, "ShopPurchase", price, itemId)
	AnalyticsService:onboardingStep(player, 4, "Purchase")
	-- Réaction visuelle : un segment file dans les tubes néon du joueur (shop → bouton).
	local roomName = player:GetAttribute("AssignedRoom")
	if type(roomName) == "string" and roomName ~= "" then
		NeonPipeColors:pulse(roomName)
	end
end
local ShopService = {
	init = function(self)
		Events.ShopPurchaseEvent.OnServerEvent:Connect(function(player, itemId)
			return handlePurchase(player, itemId)
		end)
	end,
}
return {
	ShopService = ShopService,
}
