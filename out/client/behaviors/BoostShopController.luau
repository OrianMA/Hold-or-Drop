-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local COMMUNITY = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance").COMMUNITY
-- Shop "boosts" UI — read-only multiplier readout in the ShopMenu header. Pure
-- display from replicated attributes (MultRebirth / InCommunity / MoneyTierMult /
-- MoneyMult). The shop RobuxButtons are wired by ShopItemsController (developer
-- products); the money-tier game-pass upsell lives on the HUD MultiplierBuyButton
-- (MultiplierPassController), and Community is claimed via the CommunityJoinPart
-- prompt — none of that is handled here anymore.
local player = Players.LocalPlayer
local function num(attr, fallback)
	local _condition = (player:GetAttribute(attr))
	if _condition == nil then
		_condition = fallback
	end
	return _condition
end
-- "×6", "×3.5" — trim trailing zeros.
local function fmtMult(value)
	local hundredths = math.floor(value * 100 + 1e-7)
	local trimmed = if hundredths % 100 == 0 then tostring(hundredths / 100) else string.format("%.2f", hundredths / 100)
	return `×{trimmed}`
end
local function init()
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local shop = inGameUI:WaitForChild("ShopMenu")
	local readout = shop:WaitForChild("Header"):WaitForChild("MultiplierText")
	local function refresh()
		local rebirth = num("MultRebirth", 1)
		local tier = num("MoneyTierMult", 1)
		local inCommunity = player:GetAttribute("InCommunity") == true
		local total = num("MoneyMult", 1)
		-- Le rebirth MULTIPLIE le facteur de boost ; la communauté et le palier
		-- s'additionnent à l'intérieur de ce facteur (voir ShopConfig.moneyMult).
		local boosts = 1 + (if inCommunity then COMMUNITY.mult - 1 else 0) + (tier - 1)
		readout.Text = `Money {fmtMult(total)} (Rebirth {fmtMult(rebirth)} × Boosts {fmtMult(boosts)})`
	end
	player:GetAttributeChangedSignal("MoneyMult"):Connect(refresh)
	player:GetAttributeChangedSignal("MultRebirth"):Connect(refresh)
	player:GetAttributeChangedSignal("MoneyTierMult"):Connect(refresh)
	player:GetAttributeChangedSignal("InCommunity"):Connect(refresh)
	refresh()
end
return {
	init = init,
}
