-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local nextMoneyTier = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").nextMoneyTier
-- Drives the HUD "buy multiplier pass" button
-- (InGameUI/HUD/BottomList/MultiplierBuyButton). Always offers the NEXT money-tier
-- game pass the player doesn't own yet — the MONEY_TIERS ladder in ShopBalance
-- (×2, ×4, … ×1024) — read from the replicated MoneyTierMult attribute (resolved
-- server-side by BoostService).
--   • BuyMultiplierPassFrame/RewardText                → "{mult}x Money"
--   • BuyMultiplierPassFrame/CostMovingText/CCCostText → raw Robux price (no K/M)
--   • TextButton                                       → PromptGamePassPurchase(id)
-- After a purchase BoostService re-resolves ownership; MoneyTierMult changes and
-- replicates, refreshing this to the next pass. When every tier is owned the whole
-- button hides. Client-side only — ownership + the multiplier are server-authoritative.
local player = Players.LocalPlayer
-- Robux prices per game-pass id, cached to avoid repeat GetProductInfo web calls.
local priceCache = {}
-- The pass id currently offered — guards the async price write against the offered
-- tier changing while a fetch is in flight.
local currentPassId = 0
local function moneyTierMult()
	local _condition = (player:GetAttribute("MoneyTierMult"))
	if _condition == nil then
		_condition = 1
	end
	return _condition
end
-- Robux price of a pass (cached). undefined if the web call fails / no price set.
local function fetchPrice(gamePassId)
	local _gamePassId = gamePassId
	local cached = priceCache[_gamePassId]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
	end)
	if ok and type(info) == "table" then
		local price = info.PriceInRobux
		if price ~= nil then
			local _gamePassId_1 = gamePassId
			priceCache[_gamePassId_1] = price
			return price
		end
	end
	return nil
end
local function init()
	local buyButton = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD"):WaitForChild("BottomList"):WaitForChild("MultiplierBuyButton")
	local textButton = buyButton:WaitForChild("TextButton")
	local passFrame = buyButton:WaitForChild("BuyMultiplierPassFrame")
	local rewardText = passFrame:WaitForChild("RewardText")
	local costText = passFrame:WaitForChild("CostMovingText"):WaitForChild("CCCostText")
	local function updateDisplay()
		local tier = nextMoneyTier(moneyTierMult())
		-- Every tier owned — hide the whole button + text.
		if not tier then
			currentPassId = 0
			buyButton.Visible = false
			return nil
		end
		buyButton.Visible = true
		currentPassId = tier.gamePassId
		rewardText.Text = `{tier.mult}x Money`
		local _gamePassId = tier.gamePassId
		local cached = priceCache[_gamePassId]
		if cached ~= nil then
			costText.Text = tostring(cached)
		else
			costText.Text = "..."
			task.spawn(function()
				local price = fetchPrice(tier.gamePassId)
				-- Only write if this tier is still the one on offer.
				if price ~= nil and currentPassId == tier.gamePassId then
					costText.Text = tostring(price)
				end
			end)
		end
	end
	textButton.Activated:Connect(function()
		if currentPassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, currentPassId)
		end
	end)
	player:GetAttributeChangedSignal("MoneyTierMult"):Connect(updateDisplay)
	updateDisplay()
end
return {
	init = init,
}
