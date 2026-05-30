-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local MultiplierVisuals = TS.import(script, script.Parent, "MultiplierVisuals").MultiplierVisuals
local MainUIController = TS.import(script, script.Parent, "MainUIController").MainUIController
local InformationText = TS.import(script, script.Parent, "InformationText").InformationText
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- ── Tuning ────────────────────────────────────────────────────────────────────
local FINISH_TEXT = "Finish"
local FLOAT_INTERVAL = 0.3
local CHUNK_TARGET_RATIO = 5
local MAX_CHUNK = 15
local MULTIPLIER_TWEEN_TI = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BASE_CASH_TWEEN_TI = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FRAME_FADE_OUT_TI = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Penalty animation when the player died (lossMultiplier < 1). Same TweenInfo
-- as the MainUI MoneyText counter so the two animations feel cohesive.
local LOSS_PENALTY_TI = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- BaseCash growth — same red-tinge style as the in-game multiplier label
local BASE_CASH_MAX_SIZE_INCREASE = 40
local BASE_CASH_TARGET_COLOR = Color3.new(1, 0.25, 0.25)
local FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate"
local FLOATING_FLY_TI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLOATING_BUMP_IN_TI = TweenInfo.new(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOATING_BUMP_OUT_TI = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- New "explode-out then fly" sequence: the chunk spawns on the MultiplierText,
-- disperses in a random direction, briefly holds, then flies to BaseCashText.
local FLOATING_DISPERSE_TI = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local FLOATING_DISPERSE_MIN = 70
local FLOATING_DISPERSE_MAX = 130
local FLOATING_HOLD = 0.12
-- ── Chunk split ───────────────────────────────────────────────────────────────
-- Splits `multiplier` into floating-text values that:
--  • each target multiplier / CHUNK_TARGET_RATIO (capped at MAX_CHUNK)
--  • use a max of one decimal place (so minimum chunk = 0.1)
--  • sum exactly to `multiplier`
-- Works in tenths to avoid float drift, then distributes the remainder one tenth
-- at a time across the first chunks.
local function splitMultiplier(multiplier)
	local totalUnits = math.round(multiplier * 10)
	if totalUnits <= 0 then
		return {}
	end
	local targetChunkUnits = math.max(1, math.min(MAX_CHUNK * 10, math.round(totalUnits / CHUNK_TARGET_RATIO)))
	local count = math.max(1, math.round(totalUnits / targetChunkUnits))
	local baseUnits = math.floor(totalUnits / count)
	local remainder = totalUnits - baseUnits * count
	local chunks = {}
	do
		local i = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < count) then
				break
			end
			local units = baseUnits + (if i < remainder then 1 else 0)
			local _arg0 = units / 10
			table.insert(chunks, _arg0)
		end
	end
	return chunks
end
-- ── Formatting ────────────────────────────────────────────────────────────────
local function formatMultiplier(value)
	return `{tostring(math.round(value * 10) / 10)}x`
end
local function formatCash(value)
	return FormatCash(value)
end
-- ── Floating chunk ────────────────────────────────────────────────────────────
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
local function spawnFloatingChunk(parent, chunk, originLabel, targetLabel, handlers)
	local template = getFloatingTemplate()
	if not template then
		-- Template missing — still fire callbacks so the pipeline stays coherent
		handlers.onSpawn(chunk)
		task.delay(FLOATING_DISPERSE_TI.Time + FLOATING_HOLD + FLOATING_FLY_TI.Time, function()
			return handlers.onArrived(chunk)
		end)
		return nil
	end
	local screenSize = parent.AbsoluteSize
	if screenSize.X == 0 then
		handlers.onSpawn(chunk)
		handlers.onArrived(chunk)
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
		amountLabel.Text = `+{tostring(math.round(chunk * 10) / 10)}`
	end
	local icon = frame:FindFirstChild("Icon")
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.9
	uiScale.Parent = icon or frame
	-- ── 1. Spawn exactly ON MultiplierText center ─────────────────────────────
	local _absolutePosition = originLabel.AbsolutePosition
	local _arg0 = originLabel.AbsoluteSize / 2
	local originCenter = _absolutePosition + _arg0
	frame.Position = UDim2.new(0, originCenter.X, 0, originCenter.Y)
	-- Immediate drain — happens on spawn, per spec
	handlers.onSpawn(chunk)
	-- Quick bump for that satisfying "pop" feel
	TweenService:Create(uiScale, FLOATING_BUMP_IN_TI, {
		Scale = 1.1,
	}):Play()
	task.delay(FLOATING_BUMP_IN_TI.Time, function()
		TweenService:Create(uiScale, FLOATING_BUMP_OUT_TI, {
			Scale = 1.0,
		}):Play()
	end)
	-- ── 2. Disperse in a random direction (the "explode-out") ────────────────
	local angle = math.random() * math.pi * 2
	local distance = math.random(FLOATING_DISPERSE_MIN, FLOATING_DISPERSE_MAX)
	local dispersePos = UDim2.new(0, originCenter.X + math.cos(angle) * distance, 0, originCenter.Y + math.sin(angle) * distance)
	local disperse = TweenService:Create(frame, FLOATING_DISPERSE_TI, {
		Position = dispersePos,
	})
	disperse:Play()
	disperse.Completed:Connect(function()
		-- ── 3. Brief hold so the eye registers where it landed ───────────────
		task.delay(FLOATING_HOLD, function()
			-- Target re-read at fly-time — handles UI layout shifts mid-animation.
			local _absolutePosition_1 = targetLabel.AbsolutePosition
			local _arg0_1 = targetLabel.AbsoluteSize / 2
			local targetCenter = _absolutePosition_1 + _arg0_1
			local targetPos = UDim2.new(0, targetCenter.X, 0, targetCenter.Y)
			-- ── 4. Fly to BaseCashText ───────────────────────────────────────
			local fly = TweenService:Create(frame, FLOATING_FLY_TI, {
				Position = targetPos,
			})
			fly.Completed:Connect(function()
				frame:Destroy()
				handlers.onArrived(chunk)
			end)
			fly:Play()
		end)
	end)
end
-- ── Multiplier & BaseCash visuals ─────────────────────────────────────────────
local function applyMultiplierStyle(label, value, startValue, endpoints)
	-- Hide the whole label (text + any UIStroke children) the instant we hit 0
	-- — TextSize alone leaves strokes painted, and TextTransparency doesn't
	-- affect stroke transparency. Visible=false is the only clean kill switch.
	if value <= 0 then
		label.Visible = false
		return nil
	end
	local factor = if startValue > 0 then math.clamp(value / startValue, 0, 1) else 0
	local size = endpoints.endSize + (endpoints.startSize - endpoints.endSize) * factor
	local color = endpoints.endColor:Lerp(endpoints.startColor, factor)
	label.Text = formatMultiplier(value)
	TweenService:Create(label, MULTIPLIER_TWEEN_TI, {
		TextSize = size,
		TextColor3 = color,
	}):Play()
end
local function applyBaseCashStyle(label, currentCash, baseCash, endpoints)
	local progress = if endpoints.totalGrowthCash > 0 then math.clamp((currentCash - baseCash) / endpoints.totalGrowthCash, 0, 1) else 0
	local size = endpoints.baseSize + progress * BASE_CASH_MAX_SIZE_INCREASE
	local color = endpoints.baseColor:Lerp(BASE_CASH_TARGET_COLOR, progress)
	label.Text = formatCash(currentCash)
	TweenService:Create(label, BASE_CASH_TWEEN_TI, {
		TextSize = size,
		TextColor3 = color,
	}):Play()
end
-- ── Public orchestrator ───────────────────────────────────────────────────────
-- Captured on the FIRST runEndGameAnimation call so every subsequent run can
-- reset the label back to its Studio-authored state. Without this snapshot,
-- each run would read `baseCashText.TextSize` *after* the previous run grew it,
-- so a second game would start oversized and grow again — compounding the size
-- across runs.
local initialBaseCashSize
local initialBaseCashColor
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
		frame = frame,
		multiplierText = multiplierText,
		baseCashText = baseCashText,
		screenGui = screenGui,
	}
end
-- Tweens BaseCashText value + size from (startValue, startSize) down to
-- (endValue, endSize) in parallel using LOSS_PENALTY_TI. Blocks the calling
-- task until both tweens complete, then snaps to the exact final values to
-- avoid float-precision drift. Uses a NumberValue proxy so the label re-formats
-- every frame — the player sees the number count down rather than jump-cut.
local function animateLossPenalty(label, startValue, endValue, startSize, endSize)
	local proxy = Instance.new("NumberValue")
	proxy.Value = startValue
	local conn = proxy.Changed:Connect(function(v)
		label.Text = formatCash(v)
	end)
	TweenService:Create(proxy, LOSS_PENALTY_TI, {
		Value = endValue,
	}):Play()
	local sizeTween = TweenService:Create(label, LOSS_PENALTY_TI, {
		TextSize = endSize,
	})
	sizeTween:Play()
	sizeTween.Completed:Wait()
	conn:Disconnect()
	proxy:Destroy()
	label.Text = formatCash(endValue)
	label.TextSize = endSize
end
-- Runs the full ButtonFinishGame animation, then calls onComplete().
-- Safe to call from a regular task (uses task.wait internally).
-- lossMultiplier: 1 for wins (no penalty), < 1 for kills — applied to baseCash
-- + text size via animateLossPenalty before the multiplier drain.
local flyBaseCashAndComplete
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
	-- ── Multiplier text — match the in-game label's last appearance ───────────
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
	-- Color we tween toward as the multiplier drains to 0 (size goes to 0 too
	-- — see multiplierEndpoints — so the label fully shrinks and fades out).
	local restingColor = multiplierText.TextColor3
	multiplierText.TextSize = inGameSize
	multiplierText.TextColor3 = inGameColor
	multiplierText.Text = formatMultiplier(multiplier)
	-- Re-show in case the previous run hid the label when value hit 0
	multiplierText.Visible = true
	-- ── BaseCash text — start at the button's baseCash ────────────────────────
	-- First-call snapshot — capture the true Studio-authored initial state so
	-- every subsequent run starts from the same size/color instead of compounding
	-- the previous run's growth.
	if initialBaseCashSize == nil then
		initialBaseCashSize = baseCashText.TextSize
	end
	if initialBaseCashColor == nil then
		initialBaseCashColor = baseCashText.TextColor3
	end
	local baseCashBaseSize = initialBaseCashSize
	local baseCashBaseColor = initialBaseCashColor
	-- Reset the label to its initial state WHILE it's still hidden from the
	-- previous run's fly clone — only after the reset do we flip Visible back
	-- on, so the player never sees the grown size flash.
	baseCashText.Text = formatCash(baseCash)
	baseCashText.TextSize = baseCashBaseSize
	baseCashText.TextColor3 = baseCashBaseColor
	baseCashText.Visible = true
	-- ── "Finish" flash via the shared InformationText controller (in MainUI)
	-- ─────────────────────────────────────────────────────────────────────────
	-- Show fires-and-forgets the full fade-in/hold/fade-out cycle; we just need
	-- to block until fade-in + hold are done before kicking off the penalty /
	-- drain. The fade-out then runs in parallel with the rest of the animation.
	InformationText:show(FINISH_TEXT)
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME)
	-- ── Loss penalty (killed mode only): shrink baseCash value + text size ───
	-- Runs in parallel with the finish-canvas fade-out; we block here so the
	-- drain phase below starts from the post-penalty value.
	local effectiveBaseCash = baseCash
	local effectiveBaseSize = baseCashBaseSize
	if lossMultiplier < 1 then
		effectiveBaseCash = baseCash * lossMultiplier
		effectiveBaseSize = baseCashBaseSize * lossMultiplier
		animateLossPenalty(baseCashText, baseCash, effectiveBaseCash, baseCashBaseSize, effectiveBaseSize)
	end
	-- ── Drain multiplier into base cash via floating chunks ───────────────────
	local chunks = splitMultiplier(multiplier)
	if #chunks == 0 then
		-- Nothing to animate — close after the "Finish" fade-out (penalty, if
		-- any, has already waited longer than the fade-out so no extra wait).
		if lossMultiplier >= 1 then
			task.wait(InformationText.FADE_OUT_TIME)
		end
		flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete)
		return nil
	end
	local multiplierEndpoints = {
		startSize = inGameSize,
		startColor = inGameColor,
		endSize = 0,
		endColor = restingColor,
	}
	-- ── Drain math: keep the visual final equal to what the server actually
	--    credits (= effectiveBaseCash * multiplier).
	--
	--   • Win (lossMultiplier = 1): legacy behavior — start at effectiveBaseCash,
	--     each chunk c adds effectiveBaseCash * c → final = effectiveBaseCash
	--     * (1 + multiplier).
	--   • Kill (lossMultiplier < 1): start at effectiveBaseCash (post-penalty),
	--     grow toward effectiveBaseCash * multiplier — so total growth =
	--     effectiveBaseCash * (multiplier - 1), spread across chunks that sum to
	--     `multiplier`. Per-chunk addition = perUnitCash * c.
	--     Matches the killed-mode credit formula: baseCash * multiplier *
	--     LOOSE_WIN_MULTIPLIER = effectiveBaseCash * multiplier.
	local isLoss = lossMultiplier < 1
	local perUnitCash = if isLoss and multiplier > 0 then (effectiveBaseCash * (multiplier - 1)) / multiplier else effectiveBaseCash
	local totalGrowthCash = if isLoss then effectiveBaseCash * (multiplier - 1) else effectiveBaseCash * multiplier
	local baseCashEndpoints = {
		baseSize = effectiveBaseSize,
		baseColor = baseCashBaseColor,
		totalGrowthCash = totalGrowthCash,
	}
	local remainingMultiplier = multiplier
	local currentCash = effectiveBaseCash
	local arrivedCount = 0
	local lastIndex = #chunks - 1
	for i = 0, #chunks - 1 do
		local chunk = chunks[i + 1]
		local isLastChunk = i == lastIndex
		spawnFloatingChunk(screenGui, chunk, multiplierText, baseCashText, {
			onSpawn = function(c)
				-- Spec: as soon as a floating text appears, MultiplierText drops by c.
				-- On the last chunk the residual may not hit exact 0 because of
				-- float drift across chunk subtractions — so we hard-hide the
				-- label here instead of relying on applyMultiplierStyle's
				-- `value <= 0` check. Guarantees MultiplierText disappears the
				-- instant the final "+X" pops out of it.
				if isLastChunk then
					remainingMultiplier = 0
					multiplierText.Visible = false
				else
					remainingMultiplier = math.max(0, remainingMultiplier - c)
					applyMultiplierStyle(multiplierText, remainingMultiplier, multiplier, multiplierEndpoints)
				end
			end,
			onArrived = function(c)
				-- Spec: on tween end, BaseCashText grows by c × perUnitCash
				currentCash += perUnitCash * c
				applyBaseCashStyle(baseCashText, currentCash, effectiveBaseCash, baseCashEndpoints)
				arrivedCount += 1
				if arrivedCount >= #chunks then
					task.delay(0.4, function()
						return flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete)
					end)
				end
			end,
		})
		task.wait(FLOAT_INTERVAL)
	end
end
-- Tween settings for the final "deposit" of the cash into the persistent HUD
local FLY_TO_MONEY_TI = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLY_TO_MONEY_FADE_TI = TweenInfo.new(0.55, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local FLY_TO_MONEY_SHRINK = 0.4
-- Clones BaseCashText, parents it to the ScreenGui so it can move freely across
-- the screen, hides the original (still inside the popup frame so it's reusable
-- for the next game) via Visible=false so any UIStroke children disappear with
-- it, then tweens the clone to MoneyParent (inside MainUI) while fading.
-- Falls back to an instant hide if MoneyParent isn't found.
function flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete)
	local moneyParent = MainUIController:getMoneyParent()
	local screenSize = screenGui.AbsoluteSize
	local cashAbsSize = baseCashText.AbsoluteSize
	local _absolutePosition = baseCashText.AbsolutePosition
	local _arg0 = cashAbsSize / 2
	local cashAbsCenter = _absolutePosition + _arg0
	local finishFrame = function()
		-- Reset to the captured initial size/color while still hidden so the
		-- next run opens at the Studio-authored look. We deliberately do NOT
		-- re-enable Visible here — the label must stay hidden until the popup
		-- is reopened (runEndGameAnimation flips Visible back at its top).
		if initialBaseCashSize ~= nil then
			baseCashText.TextSize = initialBaseCashSize
		end
		if initialBaseCashColor ~= nil then
			baseCashText.TextColor3 = initialBaseCashColor
		end
		onComplete()
	end
	if not moneyParent or screenSize.X == 0 or cashAbsSize.X == 0 then
		-- No target / no layout — hide and finish (label stays hidden until
		-- the next runEndGameAnimation reopens the frame).
		baseCashText.Visible = false
		finishFrame()
		return nil
	end
	local flyLabel = baseCashText:Clone()
	flyLabel.Name = "BaseCashFlyClone"
	flyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	flyLabel.Position = UDim2.new(0, cashAbsCenter.X, 0, cashAbsCenter.Y)
	flyLabel.Size = UDim2.new(0, cashAbsSize.X, 0, cashAbsSize.Y)
	flyLabel.ZIndex = 50
	flyLabel.Parent = screenGui
	-- Hide the original so the popup looks empty while the clone flies — the
	-- next run flips Visible back at the top of runEndGameAnimation.
	baseCashText.Visible = false
	local _absolutePosition_1 = moneyParent.AbsolutePosition
	local _arg0_1 = moneyParent.AbsoluteSize / 2
	local moneyCenter = _absolutePosition_1 + _arg0_1
	local targetPos = UDim2.new(0, moneyCenter.X, 0, moneyCenter.Y)
	local targetSize = UDim2.new(0, cashAbsSize.X * FLY_TO_MONEY_SHRINK, 0, cashAbsSize.Y * FLY_TO_MONEY_SHRINK)
	TweenService:Create(flyLabel, FLY_TO_MONEY_TI, {
		Position = targetPos,
		Size = targetSize,
	}):Play()
	local fadeTween = TweenService:Create(flyLabel, FLY_TO_MONEY_FADE_TI, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	fadeTween.Completed:Connect(function()
		flyLabel:Destroy()
		finishFrame()
	end)
	fadeTween:Play()
end
return {
	splitMultiplier = splitMultiplier,
	runEndGameAnimation = runEndGameAnimation,
}
