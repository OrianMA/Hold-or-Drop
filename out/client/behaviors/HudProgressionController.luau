-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local rebirthCost = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").rebirthCost
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local MoneyDisplay = TS.import(script, script.Parent.Parent, "ui", "MoneyDisplay").MoneyDisplay
local openRebirthMenu = TS.import(script, script.Parent, "RebirthMenuBehavior").openRebirthMenu
-- Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar)
-- and the rebirth button's percentage label (HUD/ButtonsFrame/RebirthFrame/PourcetageText).
-- They show the same thing as the Rebirth menu bar (RebirthMenuController): progress
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
--
-- Two display states:
--  - filling  → RebirthFrame (RebirthImage + RebirthLevelText "Rebirth N") + BackgroundFrame (money/cost)
--  - ready    → those hide, LevelUpText ("Click to rebirth") shows with a golden shimmer
--               and RebirthButton (inside the now full-width fill) opens the rebirth popup.
local player = Players.LocalPlayer
local PROGRESS_GRADIENT = "UIGradientProgress"
local FINISH_GRADIENT = "UiGradientFinish"
-- Smallest X-scale the fill is allowed to render at. Below this the sliver is too thin
-- to read (rounded corners/stroke collapse), so the fill is hidden entirely until
-- progress reaches it. At/above it, the fill never renders thinner than this.
local MIN_VISIBLE_PROGRESS = 0.013
-- Golden shimmer on LevelUpText: the gradient sweeps left → right on a loop while a
-- slow size pulse makes the label breathe.
local SHIMMER_INFO = TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local PULSE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local PULSE_SCALE = 1.08
local function getRebirths()
	local _condition = (player:GetAttribute("Rebirths"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function init()
	local hud = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD")
	local progressionBar = hud:WaitForChild("BottomList"):WaitForChild("ProgressionBar")
	local percentText = hud:WaitForChild("ButtonsFrame"):WaitForChild("RebirthFrame"):WaitForChild("PourcetageText")
	local fill = progressionBar:WaitForChild("CurrentProgressionFrame")
	local backgroundFrame = progressionBar:WaitForChild("BackgroundFrame")
	local moneyNeededText = backgroundFrame:WaitForChild("MoneyNeededText")
	local rebirthFrame = progressionBar:WaitForChild("RebirthFrame")
	local rebirthLevelText = rebirthFrame:WaitForChild("RebirthLevelText")
	local levelUpText = progressionBar:WaitForChild("LevelUpText")
	local rebirthButton = fill:WaitForChild("RebirthButton")
	local progressGradient = fill:FindFirstChild(PROGRESS_GRADIENT)
	local finishGradient = fill:FindFirstChild(FINISH_GRADIENT)
	local goldGradient = levelUpText:FindFirstChild("GoldGradient")
	local baseLevelUpSize = levelUpText.Size
	local pulsedLevelUpSize = UDim2.new(baseLevelUpSize.X.Scale * PULSE_SCALE, baseLevelUpSize.X.Offset * PULSE_SCALE, baseLevelUpSize.Y.Scale * PULSE_SCALE, baseLevelUpSize.Y.Offset * PULSE_SCALE)
	local shimmerTween = if goldGradient then TweenService:Create(goldGradient, SHIMMER_INFO, {
		Offset = Vector2.new(1, 0),
	}) else nil
	local pulseTween = TweenService:Create(levelUpText, PULSE_INFO, {
		Size = pulsedLevelUpSize,
	})
	-- The cost only changes on rebirth; cached so the per-step render stays cheap.
	local cost = rebirthCost(getRebirths())
	local lastMoney = 0
	local ready = false
	-- Swaps between the "filling" widgets and the "ready to rebirth" call to action.
	local function setReady(value)
		if ready == value then
			return nil
		end
		ready = value
		rebirthFrame.Visible = not value
		backgroundFrame.Visible = not value
		levelUpText.Visible = value
		rebirthButton.Visible = value
		if value then
			if goldGradient then
				goldGradient.Offset = Vector2.new(-1, 0)
			end
			local _result = shimmerTween
			if _result ~= nil then
				_result:Play()
			end
			pulseTween:Play()
		else
			local _result = shimmerTween
			if _result ~= nil then
				_result:Cancel()
			end
			pulseTween:Cancel()
			levelUpText.Size = baseLevelUpSize
		end
	end
	local function render(money)
		lastMoney = money
		local progress = math.clamp(money / cost, 0, 1)
		moneyNeededText.Text = `{FormatNumber(math.floor(money))} / {FormatNumber(cost)}`
		-- Whole percent, floored so it only reads "100%" once the rebirth is actually affordable.
		percentText.Text = `{math.floor(progress * 100)}%`
		local full = progress >= 1
		setReady(full)
		-- Below the minimum displayable percentage, hide the fill rather than show an
		-- unreadable sliver. At/above it, show the fill clamped to that minimum width.
		if progress < MIN_VISIBLE_PROGRESS then
			fill.Visible = false
			return nil
		end
		fill.Visible = true
		fill.Size = UDim2.new(math.max(progress, MIN_VISIBLE_PROGRESS), 0, 1, 0)
		-- Full bar → "finish" gradient, otherwise the "progress" gradient.
		if progressGradient then
			progressGradient.Enabled = not full
		end
		if finishGradient then
			finishGradient.Enabled = full
		end
	end
	local function renderRebirthLevel()
		rebirthLevelText.Text = `Rebirth {getRebirths()}`
	end
	rebirthButton.Activated:Connect(function()
		return openRebirthMenu()
	end)
	-- Mirror the animated money value so the bar counts up in sync with the HUD money.
	MoneyDisplay:subscribe(render)
	-- On rebirth the cost jumps; re-render with the current displayed money.
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		cost = rebirthCost(getRebirths())
		renderRebirthLevel()
		render(lastMoney)
	end)
	renderRebirthLevel()
	-- Force the initial state onto the widgets (setReady early-returns when unchanged).
	ready = true
	setReady(false)
end
return {
	init = init,
}
