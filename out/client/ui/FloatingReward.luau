-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local InGameUIController = TS.import(script, script.Parent, "InGameUIController").InGameUIController
local MoneyDisplay = TS.import(script, script.Parent, "MoneyDisplay").MoneyDisplay
local FloatingCash = TS.import(script, script.Parent, "FloatingCash").FloatingCash
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- ── Single "+amount" reward text ────────────────────────────────────────────────
--
-- One gain, one label: pops in the middle of the screen, jumps, holds so the eye
-- registers the amount, then ends one of two ways:
--
--   "fly"  — flies into the money HUD. Used by the losing-explosion consolation
--            (LossRewardBehavior), which re-shows the HUD first.
--   "fade" — fades out on the spot. Used when a payout is flushed because another
--            popup opened (EndGamePayoutFlushEvent): that popup hid the HUD, so
--            there is no visible counter to fly into.
--
-- Both endings bank on disappearance: MoneyDisplay.addVisual (count-up + money SFX)
-- plus EndGameFinishedEvent so the server credits the real Money through the shared
-- pendingEarned path. Banking is skipped when a rebirth invalidated the run
-- (FloatingCash generation), exactly like the end-game payout chunks.
-- Reuse the template the end-game payout sprays (a Frame holding an "Amount"
-- TextLabel), preloaded in ReplicatedStorage.
local FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate"
-- Frame name kept in sync with FloatingCash.FLOATING_FRAME_NAMES so a rebirth
-- destroys the text mid-flight.
local FRAME_NAME = "LossRewardFloatingText"
local JUMP_HEIGHT = 90
local JUMP_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local HOLD = 0.7
local FLY_TI = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_TI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- How many reward texts are currently on screen. Lets callers avoid stacking a
-- second one on top of a gain the player is already reading.
local activeCount = 0
local cachedTemplate
local function getTemplate()
	if cachedTemplate then
		return cachedTemplate
	end
	local found = ReplicatedStorage:FindFirstChild(FLOATING_TEMPLATE_NAME)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("Frame")
	end
	if _result then
		cachedTemplate = found
	end
	return cachedTemplate
end
local function getScreenGui()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local _found = playerGui
	if _found ~= nil then
		_found = _found:FindFirstChild("InGameUI")
	end
	local found = _found
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("ScreenGui")
	end
	return if _result then found else nil
end
-- Tweens every drawable part of the cloned template to fully transparent, whatever
-- the Studio author put inside it (labels, strokes, images, backgrounds).
local function fadeOut(frame, onDone)
	local parts = { frame }
	for _, desc in frame:GetDescendants() do
		table.insert(parts, desc)
	end
	for _, part in parts do
		if part:IsA("TextLabel") then
			TweenService:Create(part, FADE_TI, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif part:IsA("ImageLabel") then
			TweenService:Create(part, FADE_TI, {
				ImageTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif part:IsA("GuiObject") then
			TweenService:Create(part, FADE_TI, {
				BackgroundTransparency = 1,
			}):Play()
		elseif part:IsA("UIStroke") then
			TweenService:Create(part, FADE_TI, {
				Transparency = 1,
			}):Play()
		end
	end
	task.delay(FADE_TI.Time, onDone)
end
-- Banks the cash and tells the server to credit it. Skips banking if a rebirth
-- cancelled this run (gen went stale) — the server pending credit is cleared too.
local function bank(amount, gen, onBanked)
	activeCount = math.max(activeCount - 1, 0)
	if not FloatingCash:isStale(gen) then
		MoneyDisplay:addVisual(amount)
		Events.EndGameFinishedEvent:FireServer()
	end
	local _result = onBanked
	if _result ~= nil then
		_result()
	end
end
local function spawn(amount, ending, onBanked)
	local template = getTemplate()
	local screenGui = getScreenGui()
	local runGen = FloatingCash:current()
	local flyTarget = if ending == "fly" then InGameUIController:getMoneyParent() else nil
	activeCount += 1
	-- No template / no laid-out screen / no fly target — still bank so the credit lands.
	if not template or not screenGui or screenGui.AbsoluteSize.X == 0 or (ending == "fly" and not flyTarget) then
		bank(amount, runGen, onBanked)
		return nil
	end
	local center = screenGui.AbsoluteSize / 2
	local frame = template:Clone()
	frame.Name = FRAME_NAME
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 30
	frame.Position = UDim2.new(0, center.X, 0, center.Y)
	frame.Visible = true
	frame.Parent = screenGui
	local amountLabel = frame:FindFirstChild("Amount")
	if amountLabel then
		amountLabel.Text = `+{FormatCash(amount)}`
	end
	local finish = function()
		frame:Destroy()
		bank(amount, runGen, onBanked)
	end
	-- 1. Jump up.
	local jump = TweenService:Create(frame, JUMP_TI, {
		Position = UDim2.new(0, center.X, 0, center.Y - JUMP_HEIGHT),
	})
	jump.Completed:Connect(function()
		-- 2. Brief hold, then the chosen ending.
		task.delay(HOLD, function()
			-- A rebirth may have destroyed the frame while it was holding.
			if frame.Parent == nil then
				bank(amount, runGen, onBanked)
				return nil
			end
			if not flyTarget then
				fadeOut(frame, finish)
				return nil
			end
			-- 3. Fly to the money HUD (target re-read at fly-time).
			local _absolutePosition = flyTarget.AbsolutePosition
			local _arg0 = flyTarget.AbsoluteSize / 2
			local targetCenter = _absolutePosition + _arg0
			local fly = TweenService:Create(frame, FLY_TI, {
				Position = UDim2.new(0, targetCenter.X, 0, targetCenter.Y),
			})
			fly.Completed:Connect(finish)
			fly:Play()
		end)
	end)
	jump:Play()
end
local FloatingReward = {
	isActive = function(self)
		return activeCount > 0
	end,
	show = function(self, amount, ending, onBanked)
		task.spawn(function()
			return spawn(amount, ending, onBanked)
		end)
	end,
}
return {
	FloatingReward = FloatingReward,
}
