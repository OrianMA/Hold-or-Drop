-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local ITEMS = _ShopConfig.ITEMS
local isAtCap = _ShopConfig.isAtCap
local priceForItem = _ShopConfig.priceForItem
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
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
		Events.InformationTextEvent:FireClient(player, "Niveau maximum atteint", DENIED_COLOR)
		return nil
	end
	local price = priceForItem(item, level)
	if PlayerDataService:get(player, "Money") < price then
		Events.InformationTextEvent:FireClient(player, "Pas assez d'argent", DENIED_COLOR)
		return nil
	end
	PlayerDataService:add(player, "Money", -price)
	PlayerProgressionService:addLevel(player, item.stat, item.quantity)
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
