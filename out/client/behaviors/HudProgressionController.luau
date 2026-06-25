-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local rebirthCost = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").rebirthCost
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local MoneyDisplay = TS.import(script, script.Parent.Parent, "ui", "MoneyDisplay").MoneyDisplay
-- Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar).
-- It shows the same thing as the Rebirth menu bar (RebirthMenuController): progress
-- toward the next rebirth, Money / rebirthCost(Rebirths).
--
-- Instead of running its own tween, the bar MIRRORS the money HUD's displayed value
-- (MoneyDisplay.subscribe) — so the fill and the "money / cost" number count up in
-- perfect lockstep with the money counter, at the same speed, including the cosmetic
-- payout count-up. The cost only changes on rebirth.
--
-- The fill also swaps its gradient: the "progress" gradient while filling, and the
-- "finish" gradient once the bar is full (money >= cost). Both gradients are authored
-- inside CurrentProgressionFrame in Studio.
local player = Players.LocalPlayer
local PROGRESS_GRADIENT = "UIGradientProgress"
local FINISH_GRADIENT = "UiGradientFinish"
local function getRebirths()
	local _condition = (player:GetAttribute("Rebirths"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function init()
	local progressionBar = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD"):WaitForChild("BottomList"):WaitForChild("ProgressionBar")
	local fill = progressionBar:WaitForChild("CurrentProgressionFrame")
	local moneyNeededText = progressionBar:WaitForChild("BackgroundFrame"):WaitForChild("MoneyNeededText")
	local progressGradient = fill:FindFirstChild(PROGRESS_GRADIENT)
	local finishGradient = fill:FindFirstChild(FINISH_GRADIENT)
	-- The cost only changes on rebirth; cached so the per-step render stays cheap.
	local cost = rebirthCost(getRebirths())
	local lastMoney = 0
	local function render(money)
		lastMoney = money
		local progress = math.clamp(money / cost, 0, 1)
		fill.Size = UDim2.new(progress, 0, 1, 0)
		moneyNeededText.Text = `{FormatNumber(math.floor(money))} / {FormatNumber(cost)}`
		-- Full bar → "finish" gradient, otherwise the "progress" gradient.
		local full = progress >= 1
		if progressGradient then
			progressGradient.Enabled = not full
		end
		if finishGradient then
			finishGradient.Enabled = full
		end
	end
	-- Mirror the animated money value so the bar counts up in sync with the HUD money.
	MoneyDisplay:subscribe(render)
	-- On rebirth the cost jumps; re-render with the current displayed money.
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		cost = rebirthCost(getRebirths())
		render(lastMoney)
	end)
end
return {
	init = init,
}
