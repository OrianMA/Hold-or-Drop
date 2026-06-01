-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local MultiplierVisuals = TS.import(script, script.Parent, "MultiplierVisuals").MultiplierVisuals
local MainUIController = TS.import(script, script.Parent, "MainUIController").MainUIController
local MoneyDisplay = TS.import(script, script.Parent, "MoneyDisplay").MoneyDisplay
local InformationText = TS.import(script, script.Parent, "InformationText").InformationText
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- ── ButtonFinishGame payout animation ───────────────────────────────────────────
--
-- Sequence (after the "Finish" flash + optional kill penalty):
--   1. MultiplierText flies into BaseCashText and disappears (no floating text).
--   2. BaseCashText counts up from its base value to the total earned (grow + red).
--   3. BaseCashText stays put and sprays N floating texts toward the money HUD.
--      Each spawn drops BaseCashText's value + size by one chunk (down to 0); each
--      arrival bumps the player's HUD money up by that chunk.
-- ── Tuning ──────────────────────────────────────────────────────────────────────
local FINISH_TEXT = "Finish"
-- Phase 1 — MultiplierText merging into BaseCashText.
local MULTIPLIER_MERGE_TI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Phase 2 — BaseCashText counting up to the total earned.
local BASE_CASH_COUNTUP_TI = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Phase 3 — how many floating texts BaseCashText sprays, and how fast.
-- Both tweakable: COUNT splits the total earned into COUNT chunks of
-- totalEarn / COUNT; INTERVAL is the delay between each spawn.
local FLOATING_TEXT_COUNT = 8
local FLOATING_TEXT_INTERVAL = 0.12
-- Penalty animation when the player died (lossMultiplier < 1).
local LOSS_PENALTY_TI = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- BaseCash growth — red-tinge style matching the in-game multiplier label.
local BASE_CASH_MAX_SIZE_INCREASE = 40
local BASE_CASH_TARGET_COLOR = Color3.new(1, 0.25, 0.25)
-- Floating chunk: spawn on the origin, disperse in a random direction, hold,
-- then fly to the target. Same feel as the in-game floating labels.
local FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate"
local FLOATING_FLY_TI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLOATING_BUMP_IN_TI = TweenInfo.new(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOATING_BUMP_OUT_TI = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOATING_DISPERSE_TI = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local FLOATING_DISPERSE_MIN = 70
local FLOATING_DISPERSE_MAX = 130
local FLOATING_HOLD = 0.12
-- ── Formatting ────────────────────────────────────────────────────────────────
local function formatMultiplier(value)
	return `{tostring(math.round(value * 10) / 10)}x`
end
local function formatCash(value)
	return FormatCash(value)
end
-- ── Floating chunk ──────────────────────────────────────────────────────────────
local cachedTemplate
local function getFloatingTemplate()
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
-- Spawns a floating "+amount" on `origin`, disperses it, then flies it to
-- `target`. onSpawn fires immediately; onArrived fires when the fly completes.
local function spawnFloatingChunk(parent, amount, origin, target, handlers)
	local template = getFloatingTemplate()
	if not template then
		-- Template missing — still fire callbacks so the pipeline stays coherent.
		handlers.onSpawn()
		task.delay(FLOATING_DISPERSE_TI.Time + FLOATING_HOLD + FLOATING_FLY_TI.Time, function()
			return handlers.onArrived()
		end)
		return nil
	end
	local screenSize = parent.AbsoluteSize
	if screenSize.X == 0 then
		handlers.onSpawn()
		handlers.onArrived()
		return nil
	end
	local frame = template:Clone()
	frame.Name = "EndGameFloatingChunk"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 30
	frame.Visible = true
	frame.Parent = parent
	local amountLabel = frame:FindFirstChild("Amount")
	if amountLabel then
		amountLabel.Text = `+{formatCash(amount)}`
	end
	local icon = frame:FindFirstChild("Icon")
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.9
	uiScale.Parent = icon or frame
	-- 1. Spawn on the origin's center.
	local _absolutePosition = origin.AbsolutePosition
	local _arg0 = origin.AbsoluteSize / 2
	local originCenter = _absolutePosition + _arg0
	frame.Position = UDim2.new(0, originCenter.X, 0, originCenter.Y)
	handlers.onSpawn()
	-- Quick bump for a satisfying "pop".
	TweenService:Create(uiScale, FLOATING_BUMP_IN_TI, {
		Scale = 1.1,
	}):Play()
	task.delay(FLOATING_BUMP_IN_TI.Time, function()
		TweenService:Create(uiScale, FLOATING_BUMP_OUT_TI, {
			Scale = 1.0,
		}):Play()
	end)
	-- 2. Disperse in a random direction.
	local angle = math.random() * math.pi * 2
	local distance = math.random(FLOATING_DISPERSE_MIN, FLOATING_DISPERSE_MAX)
	local dispersePos = UDim2.new(0, originCenter.X + math.cos(angle) * distance, 0, originCenter.Y + math.sin(angle) * distance)
	local disperse = TweenService:Create(frame, FLOATING_DISPERSE_TI, {
		Position = dispersePos,
	})
	disperse:Play()
	disperse.Completed:Connect(function()
		-- 3. Brief hold so the eye registers where it landed.
		task.delay(FLOATING_HOLD, function()
			-- Target re-read at fly-time — handles layout shifts mid-animation.
			local _absolutePosition_1 = target.AbsolutePosition
			local _arg0_1 = target.AbsoluteSize / 2
			local targetCenter = _absolutePosition_1 + _arg0_1
			local targetPos = UDim2.new(0, targetCenter.X, 0, targetCenter.Y)
			-- 4. Fly to the target.
			local fly = TweenService:Create(frame, FLOATING_FLY_TI, {
				Position = targetPos,
			})
			fly.Completed:Connect(function()
				frame:Destroy()
				handlers.onArrived()
			end)
			fly:Play()
		end)
	end)
end
-- ── Blocking value/size/color tween for BaseCashText ─────────────────────────────
-- Tweens BaseCashText's value (via a NumberValue proxy so it re-formats every
-- frame), text size and color from start to end in parallel, blocking until done,
-- then snaps to the exact end values to avoid float drift.
local function animateCash(label, startValue, endValue, startSize, endSize, startColor, endColor, ti)
	label.Text = formatCash(startValue)
	label.TextSize = startSize
	label.TextColor3 = startColor
	local proxy = Instance.new("NumberValue")
	proxy.Value = startValue
	local conn = proxy.Changed:Connect(function(v)
		label.Text = formatCash(v)
	end)
	TweenService:Create(proxy, ti, {
		Value = endValue,
	}):Play()
	local styleTween = TweenService:Create(label, ti, {
		TextSize = endSize,
		TextColor3 = endColor,
	})
	styleTween:Play()
	styleTween.Completed:Wait()
	conn:Disconnect()
	proxy:Destroy()
	label.Text = formatCash(endValue)
	label.TextSize = endSize
	label.TextColor3 = endColor
end
-- ── Phase 1: MultiplierText flies into BaseCashText, then disappears ─────────────
local function mergeMultiplierIntoBaseCash(multiplierText, baseCashText)
	-- Both labels share the same parent + anchor (0.5, 0.5), so copying Position
	-- lands the multiplier squarely on the base cash.
	local tween = TweenService:Create(multiplierText, MULTIPLIER_MERGE_TI, {
		Position = baseCashText.Position,
	})
	tween:Play()
	tween.Completed:Wait()
	multiplierText.Visible = false
end
-- ── Orchestrator ────────────────────────────────────────────────────────────────
local function resolveRefs(frame)
	local multiplierText = frame:WaitForChild("MultiplierText", 5)
	local baseCashText = frame:WaitForChild("BaseCashText", 5)
	local screenGui = frame:FindFirstAncestorOfClass("ScreenGui")
	local _result = multiplierText
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	local _condition = not _result
	if not _condition then
		local _result_1 = baseCashText
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("TextLabel")
		end
		_condition = not _result_1
		if not _condition then
			_condition = not screenGui
		end
	end
	if _condition then
		warn("EndGameAnimation: missing one of MultiplierText/BaseCashText")
		return nil
	end
	return {
		multiplierText = multiplierText,
		baseCashText = baseCashText,
		screenGui = screenGui,
	}
end
-- First-call snapshots — capture the Studio-authored state so every run resets to
-- the same baseline instead of compounding the previous run's growth/move.
local initialBaseCashSize
local initialBaseCashColor
local initialMultiplierPosition
local initialMultiplierTransparency
-- Runs the full ButtonFinishGame animation, then calls onComplete().
-- Safe to call from a regular task (uses task.wait internally).
local function runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, onComplete)
	local refs = resolveRefs(frame)
	if not refs then
		onComplete()
		return nil
	end
	local _binding = refs
	local multiplierText = _binding.multiplierText
	local baseCashText = _binding.baseCashText
	local screenGui = _binding.screenGui
	if initialBaseCashSize == nil then
		initialBaseCashSize = baseCashText.TextSize
	end
	if initialBaseCashColor == nil then
		initialBaseCashColor = baseCashText.TextColor3
	end
	if initialMultiplierPosition == nil then
		initialMultiplierPosition = multiplierText.Position
	end
	if initialMultiplierTransparency == nil then
		initialMultiplierTransparency = multiplierText.TextTransparency
	end
	local baseSize = initialBaseCashSize
	local baseColor = initialBaseCashColor
	-- ── Reset MultiplierText — match the in-game label's last appearance ──────────
	local snapshot = MultiplierVisuals:getLast()
	local _result = snapshot
	if _result ~= nil then
		_result = _result.size
	end
	local _condition = _result
	if _condition == nil then
		_condition = multiplierText.TextSize
	end
	local inGameSize = _condition
	local _result_1 = snapshot
	if _result_1 ~= nil then
		_result_1 = _result_1.color
	end
	local _condition_1 = _result_1
	if _condition_1 == nil then
		_condition_1 = multiplierText.TextColor3
	end
	local inGameColor = _condition_1
	multiplierText.Position = initialMultiplierPosition
	multiplierText.TextTransparency = initialMultiplierTransparency
	multiplierText.TextSize = inGameSize
	multiplierText.TextColor3 = inGameColor
	multiplierText.Text = formatMultiplier(multiplier)
	multiplierText.Visible = true
	-- ── Reset BaseCashText to its base value/look ─────────────────────────────────
	baseCashText.Text = formatCash(baseCash)
	baseCashText.TextSize = baseSize
	baseCashText.TextColor3 = baseColor
	baseCashText.Visible = true
	-- ── "Finish" flash (blocks through fade-in + hold) ───────────────────────────
	InformationText:show(FINISH_TEXT)
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME)
	-- ── Kill penalty: shrink BaseCashText value + size before the count-up ────────
	local effectiveBaseCash = baseCash
	local effectiveBaseSize = baseSize
	if lossMultiplier < 1 then
		effectiveBaseCash = baseCash * lossMultiplier
		effectiveBaseSize = baseSize * lossMultiplier
		animateCash(baseCashText, baseCash, effectiveBaseCash, baseSize, effectiveBaseSize, baseColor, baseColor, LOSS_PENALTY_TI)
	end
	-- ── Phase 1: MultiplierText merges into BaseCashText and disappears ───────────
	mergeMultiplierIntoBaseCash(multiplierText, baseCashText)
	-- ── Phase 2: BaseCashText counts up to the total earned ───────────────────────
	local totalEarn = effectiveBaseCash * multiplier
	local grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE
	animateCash(baseCashText, effectiveBaseCash, totalEarn, effectiveBaseSize, grownSize, baseColor, BASE_CASH_TARGET_COLOR, BASE_CASH_COUNTUP_TI)
	-- ── Phase 3: spray N floating texts into the money HUD ────────────────────────
	local moneyParent = MainUIController:getMoneyParent()
	local n = FLOATING_TEXT_COUNT
	local chunk = if n > 0 then totalEarn / n else 0
	local finishReset = function()
		-- Leave BaseCashText hidden but reset to the Studio baseline for next run.
		baseCashText.Visible = false
		if initialBaseCashSize ~= nil then
			baseCashText.TextSize = initialBaseCashSize
		end
		if initialBaseCashColor ~= nil then
			baseCashText.TextColor3 = initialBaseCashColor
		end
	end
	-- No HUD target / nothing to spray → deposit visually and finish.
	if not moneyParent or n <= 0 or totalEarn <= 0 then
		if totalEarn > 0 then
			MoneyDisplay:addVisual(totalEarn)
		end
		finishReset()
		onComplete()
		return nil
	end
	local arrived = 0
	for i = 1, n do
		local isLast = i == n
		local remaining = if isLast then 0 else totalEarn - i * chunk
		spawnFloatingChunk(screenGui, chunk, baseCashText, moneyParent, {
			onSpawn = function()
				-- Floating text leaving drops BaseCashText by one chunk (value + size).
				baseCashText.Text = formatCash(remaining)
				local ratio = if totalEarn > 0 then remaining / totalEarn else 0
				baseCashText.TextSize = baseSize + (grownSize - baseSize) * ratio
				baseCashText.TextColor3 = baseColor:Lerp(BASE_CASH_TARGET_COLOR, ratio)
				if isLast then
					baseCashText.Visible = false
				end
			end,
			onArrived = function()
				MoneyDisplay:addVisual(chunk)
				arrived += 1
				if arrived >= n then
					finishReset()
					task.delay(0.2, onComplete)
				end
			end,
		})
		task.wait(FLOATING_TEXT_INTERVAL)
	end
end
return {
	runEndGameAnimation = runEndGameAnimation,
}
