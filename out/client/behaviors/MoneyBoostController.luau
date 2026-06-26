-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- Drives the HUD money-boost readout (InGameUI/HUD/BottomList/ProgressionBar/MoneyBoostText).
-- Shows the money multiplier the player currently gets from money-tier game passes only —
-- the MONEY_TIERS ladder resolved server-side by BoostService into the replicated
-- MoneyTierMult attribute (the highest owned tier wins; defaults to 1 when none is owned).
--   • MoneyTierMult > 1 → "{mult}x money boost", text visible
--   • MoneyTierMult = 1 → no money-tier pass owned, hide the text
-- Client-side display only — the multiplier is server-authoritative.
local player = Players.LocalPlayer
local function moneyTierMult()
	local _condition = (player:GetAttribute("MoneyTierMult"))
	if _condition == nil then
		_condition = 1
	end
	return _condition
end
local function init()
	local boostText = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD"):WaitForChild("BottomList"):WaitForChild("ProgressionBar"):WaitForChild("MoneyBoostText")
	local function updateDisplay()
		local mult = moneyTierMult()
		-- No money-tier pass owned — hide the readout.
		if mult <= 1 then
			boostText.Visible = false
			return nil
		end
		boostText.Visible = true
		boostText.Text = `{mult}x money boost`
	end
	player:GetAttributeChangedSignal("MoneyTierMult"):Connect(updateDisplay)
	updateDisplay()
end
return {
	init = init,
}
