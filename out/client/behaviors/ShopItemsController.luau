-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local ITEM_ORDER = _ShopConfig.ITEM_ORDER
local ITEMS = _ShopConfig.ITEMS
local STATS = _ShopConfig.STATS
local isAtCap = _ShopConfig.isAtCap
local priceForItem = _ShopConfig.priceForItem
local levelProductForStat = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "LevelProducts").levelProductForStat
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local InformationText = TS.import(script, script.Parent.Parent, "ui", "InformationText").InformationText
-- Wires the four shop item frames (InGameUI/ShopMenu/Body/*). Read-only display
-- driven by replicated attributes (Money + the per-stat level attributes); the
-- cash BuyButton fires ShopPurchaseEvent, the RobuxButton prompts a developer
-- product (shared/LevelProducts.ts). The server re-validates every purchase, so
-- the client guards here are purely for instant UX.
local player = Players.LocalPlayer
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
-- Robux price per dev product (GetProductInfo is a web call — fetch once, cache).
local robuxPriceCache = {}
local function fetchRobuxPrice(productId, label)
	local _productId = productId
	local cached = robuxPriceCache[_productId]
	if cached ~= nil then
		label.Text = tostring(cached)
		return nil
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" then
			local _condition = info.PriceInRobux
			if _condition == nil then
				_condition = 0
			end
			local price = _condition
			local _productId_1 = productId
			robuxPriceCache[_productId_1] = price
			label.Text = tostring(price)
		end
	end)
end
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
-- Multiplicateur d'argent répliqué (rebirth × boosts) — sert à afficher le gain
-- EFFECTIF de BaseCash au lieu de sa valeur brute.
local function getMoneyMult()
	local _condition = (player:GetAttribute("MoneyMult"))
	if _condition == nil then
		_condition = 1
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
	local buttons = frame:WaitForChild("ButtonsLayout")
	local buyButton = buttons:WaitForChild("BuyButton")
	local priceLabel = buyButton:WaitForChild("TextLabel")
	local cfg = STATS[item.stat]
	titleText.Text = item.title
	-- Robux dev product (grants `levels` of this stat).
	local robuxButton = buttons:WaitForChild("RobuxButton")
	local robuxGainLabel = robuxButton:WaitForChild("GainQuantityText")
	local robuxPriceLabel = robuxButton:WaitForChild("RobuxQuantityText")
	local product = levelProductForStat(item.stat)
	if product then
		robuxGainLabel.Text = `+{product.levels} niv.`
		fetchRobuxPrice(product.productId, robuxPriceLabel)
		robuxButton.Activated:Connect(function()
			-- Refuse at the cap (Resistance): no prompt, just inform the player.
			if isAtCap(item.stat, getLevel(cfg.levelAttribute)) then
				InformationText:show("Niveau maximum atteint", DENIED_COLOR)
				return nil
			end
			MarketplaceService:PromptProductPurchase(player, product.productId)
		end)
	end
	local function refresh()
		local level = getLevel(cfg.levelAttribute)
		local ctx = {
			moneyMult = getMoneyMult(),
		}
		currentText.Text = cfg.display(cfg.valueFor(level), ctx)
		if isAtCap(item.stat, level) then
			nextText.Text = "MAX"
			priceLabel.Text = "MAX"
			setAffordable(buyButton, priceLabel, false)
			-- Grey the Robux button too — it refuses the purchase at the cap.
			if product then
				robuxGainLabel.Text = "MAX"
				robuxButton.AutoButtonColor = false
				robuxButton.BackgroundTransparency = 0.6
			end
			return nil
		end
		nextText.Text = cfg.display(cfg.valueFor(level + item.quantity), ctx)
		local price = priceForItem(item, level)
		priceLabel.Text = `{FormatNumber(price)}$`
		setAffordable(buyButton, priceLabel, getMoney() >= price)
		-- Restore the Robux button (e.g. Resistance dropped back below cap on rebirth).
		if product then
			robuxGainLabel.Text = `+{product.levels} niv.`
			robuxButton.AutoButtonColor = true
			robuxButton.BackgroundTransparency = 0
		end
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
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local body = inGameUI:WaitForChild("ShopMenu"):WaitForChild("Body")
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
	player:GetAttributeChangedSignal("RocketSpeedLevel"):Connect(refreshAll)
	player:GetAttributeChangedSignal("ResistanceLevel"):Connect(refreshAll)
	-- Un rebirth change MoneyMult → le gain effectif affiché sur BaseCash doit suivre.
	player:GetAttributeChangedSignal("MoneyMult"):Connect(refreshAll)
end
return {
	init = init,
}
