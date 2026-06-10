-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local ITEM_ORDER = _ShopConfig.ITEM_ORDER
local ITEMS = _ShopConfig.ITEMS
local STATS = _ShopConfig.STATS
local isAtCap = _ShopConfig.isAtCap
local priceForItem = _ShopConfig.priceForItem
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
-- Wires the four shop item frames (MainUI/ShopMenu/Body/*). Read-only display
-- driven by replicated attributes (Money + the per-stat level attributes); the
-- cash button fires ShopPurchaseEvent. The server re-validates every purchase,
-- so the client guard here is purely for instant UX.
--
-- Robux buttons (RobuxButton) are intentionally left untouched — not wired yet.
local player = Players.LocalPlayer
local function getLevel(levelAttribute)
	local _condition = (player:GetAttribute(levelAttribute))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function getMoney()
	local _condition = (player:GetAttribute("Money"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
-- Cosmetic only — the real gate is the handler guard + server validation.
local function setAffordable(button, priceLabel, affordable)
	button.AutoButtonColor = affordable
	button.BackgroundTransparency = if affordable then 0 else 0.6
	priceLabel.TextTransparency = if affordable then 0 else 0.4
end
-- Returns a refresh closure that re-renders the frame from current attributes.
local function bindItem(body, item)
	local frame = body:WaitForChild(item.frameName)
	local boost = frame:WaitForChild("BoostLyout")
	local titleText = boost:WaitForChild("BoostTitleText")
	local currentText = boost:WaitForChild("CurrentStatFrame"):WaitForChild("CurrentStatText")
	local nextText = boost:WaitForChild("NextStatFrame"):WaitForChild("NextStatText")
	local buyButton = frame:WaitForChild("ButtonsLayout"):WaitForChild("BuyButton")
	local priceLabel = buyButton:WaitForChild("TextLabel")
	local cfg = STATS[item.stat]
	titleText.Text = item.title
	local function refresh()
		local level = getLevel(cfg.levelAttribute)
		currentText.Text = cfg.display(cfg.valueFor(level))
		if isAtCap(item.stat, level) then
			nextText.Text = "MAX"
			priceLabel.Text = "MAX"
			setAffordable(buyButton, priceLabel, false)
			return nil
		end
		nextText.Text = cfg.display(cfg.valueFor(level + item.quantity))
		local price = priceForItem(item, level)
		priceLabel.Text = `{FormatNumber(price)}$`
		setAffordable(buyButton, priceLabel, getMoney() >= price)
	end
	buyButton.Activated:Connect(function()
		local level = getLevel(cfg.levelAttribute)
		if isAtCap(item.stat, level) then
			return nil
		end
		if getMoney() < priceForItem(item, level) then
			return nil
		end
		Events.ShopPurchaseEvent:FireServer(item.id)
	end)
	refresh()
	return refresh
end
local function init()
	local mainUI = (player:WaitForChild("PlayerGui")):WaitForChild("MainUI")
	local body = mainUI:WaitForChild("ShopMenu"):WaitForChild("Body")
	local refreshers = {}
	for _, id in ITEM_ORDER do
		local _arg0 = bindItem(body, ITEMS[id])
		table.insert(refreshers, _arg0)
	end
	local refreshAll = function()
		for _, refresh in refreshers do
			refresh()
		end
	end
	-- Money affects every item's affordability; each level attribute changes the
	-- stat display + next price. Refresh everything on any of them for simplicity.
	player:GetAttributeChangedSignal("Money"):Connect(refreshAll)
	player:GetAttributeChangedSignal("BaseCashLevel"):Connect(refreshAll)
	player:GetAttributeChangedSignal("MultiplierLevel"):Connect(refreshAll)
	player:GetAttributeChangedSignal("SafetyLevel"):Connect(refreshAll)
end
return {
	init = init,
}
