-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local SAFETY_PASS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance").SAFETY_PASS
local nextMoneyTier = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").nextMoneyTier
local InformationText = TS.import(script, script.Parent.Parent, "ui", "InformationText").InformationText
-- Shop "boosts" UI — read-only multiplier readout + two Robux upsell buttons.
-- Pure display from replicated attributes (MultRebirth / InCommunity /
-- MoneyTierMult / MoneyMult); the buttons prompt a game-pass purchase. A pass
-- whose id is 0 is INERT: the button shows a "soon" state and does nothing.
-- Community is claimed in-world via the CommunityJoinPart prompt, not here.
local player = Players.LocalPlayer
local SOON_COLOR = Color3.new(1, 0.85, 0.4)
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
-- Resolves RobuxButton/GainQuantityText if present (label of the gained boost).
local function gainLabel(robux)
	local found = robux:FindFirstChild("GainQuantityText")
	return if found and found:IsA("TextLabel") then found else nil
end
-- Wires a RobuxButton to prompt `gamePassId`; inert (with a "soon" gain label)
-- when the id is 0. `gainText` is the boost it grants (e.g. "×4", "+20% safety").
local function bindRobux(robux, gamePassId, gainText)
	local label = gainLabel(robux)
	if label then
		label.Text = if gamePassId > 0 then gainText else "Bientôt"
		if gamePassId <= 0 then
			label.TextColor3 = SOON_COLOR
		end
	end
	robux.Activated:Connect(function()
		if gamePassId <= 0 then
			InformationText:show("Bientôt disponible", SOON_COLOR)
			return nil
		end
		MarketplaceService:PromptGamePassPurchase(player, gamePassId)
	end)
end
local function init()
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local shop = inGameUI:WaitForChild("ShopMenu")
	local body = shop:WaitForChild("Body")
	local readout = shop:WaitForChild("Header"):WaitForChild("MultiplierText")
	local moneyRobux = body:WaitForChild("AButtonMoney"):WaitForChild("ButtonsLayout"):WaitForChild("RobuxButton")
	local safetyRobux = body:WaitForChild("DSafety"):WaitForChild("ButtonsLayout"):WaitForChild("RobuxButton")
	-- Money-tier upsell: show the NEXT tier above what the player owns.
	local tierMult = num("MoneyTierMult", 1)
	local nextTier = nextMoneyTier(tierMult)
	bindRobux(moneyRobux, if nextTier then nextTier.gamePassId else 0, if nextTier then fmtMult(nextTier.mult) else "MAX")
	-- Safety pass: flat +20% (the pass id; inert at 0).
	bindRobux(safetyRobux, SAFETY_PASS.gamePassId, "+20% safety")
	local function refresh()
		local rebirth = num("MultRebirth", 1)
		local tier = num("MoneyTierMult", 1)
		local inCommunity = player:GetAttribute("InCommunity") == true
		local total = num("MoneyMult", 1)
		local community = if inCommunity then "×2" else "×1"
		readout.Text = `Money {fmtMult(total)}  (Rebirth {fmtMult(rebirth)} · Communauté {community} · Palier {fmtMult(tier)})`
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
