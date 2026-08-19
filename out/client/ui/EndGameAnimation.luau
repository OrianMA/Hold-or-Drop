-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local MultiplierVisuals = TS.import(script, script.Parent, "MultiplierVisuals").MultiplierVisuals
local InGameUIController = TS.import(script, script.Parent, "InGameUIController").InGameUIController
local MoneyDisplay = TS.import(script, script.Parent, "MoneyDisplay").MoneyDisplay
local FloatingCash = TS.import(script, script.Parent, "FloatingCash").FloatingCash
local InformationText = TS.import(script, script.Parent, "InformationText").InformationText
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- ── ButtonFinishGame payout animation ───────────────────────────────────────────
--
-- Sequence (after the "Finish" flash + optional kill penalty):
--   0.  Claim bonus (Perfect ×3 / Critical ×10, claimBonus > 1): BaseCashText counts up
--       from the raw base to the boosted base with a golden bump — the bonus multiplies
--       the BASE CASH, never the multiplier, and this phase is what shows it.
--   1.  MultiplierText flies into BaseCashText and disappears.
--   2.  BaseCashText counts up by the in-game multiplier (grow + red).
--       EffectiveBaseCash already folds in every money multiplier, so no separate
--       rebirth phase is needed.
--   3.  BaseCashText stays put (showing the full total) and sprays N floating texts
--       toward the money HUD; each arrival banks one chunk of the total.
--   4.  After the chunks land, a short pause, then the whole BaseCashText label flies
--       to the HUD cash as the final move.
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
-- Phase 0 — claim bonus (Perfect ×3 / Critical ×10) growing the BASE CASH.
-- Le compteur monte en doré (couleur du flash Critical) et le texte gonfle, puis
-- redescend à sa taille/couleur de base pour que la phase multiplicateur reparte propre.
local CLAIM_BONUS_TI = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLAIM_BONUS_SETTLE_TI = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLAIM_BONUS_COLOR = Color3.fromRGB(255, 200, 60)
local CLAIM_BONUS_SIZE_INCREASE = 30
local CLAIM_BONUS_HOLD = 0.35
local CLAIM_BONUS_BANNER_HOLD = 1.6
-- Penalty animation when the player died (lossMultiplier < 1).
local LOSS_PENALTY_TI = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- BaseCash growth — red-tinge style matching the in-game multiplier label.
local BASE_CASH_MAX_SIZE_INCREASE = 40
local BASE_CASH_TARGET_COLOR = Color3.new(1, 0.25, 0.25)
-- Floating chunk: spawn on the origin, disperse in a random direction, hold,
-- then fly to the target. Same feel as the in-game floating labels.
local FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate"
local FLOATING_FLY_TI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLOATING_DISPERSE_TI = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local FLOATING_DISPERSE_MIN = 70
local FLOATING_DISPERSE_MAX = 130
local FLOATING_HOLD = 0.12
-- Phase 4 — after the spray, the whole BaseCashText label flies to the HUD money.
local FINAL_MOVE_DELAY = 0.45
local BASE_CASH_FLY_TI = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- ── Formatting ────────────────────────────────────────────────────────────────
-- 2 décimales (0.01 près) — pas d'arrondi, pour afficher EXACTEMENT le multiplicateur
-- verrouillé au claim (la popup de fin reçoit `claimedMultiplier`, voir §6.3).
local function formatMultiplier(value)
	return `{string.format("%.2f", value)}x`
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
	-- 1. Spawn on the origin's center (at native size — no spawn bump).
	local _absolutePosition = origin.AbsolutePosition
	local _arg0 = origin.AbsoluteSize / 2
	local originCenter = _absolutePosition + _arg0
	frame.Position = UDim2.new(0, originCenter.X, 0, originCenter.Y)
	handlers.onSpawn()
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
-- ── Phase 4: the whole BaseCashText label flies to the HUD money ─────────────────
-- Clones BaseCashText to the ScreenGui (so the original resets cleanly), hides the
-- original, and flies the clone onto the HUD money. Cosmetic — the chunks already
-- banked the cash. onArrived fires when the clone lands.
local initialBaseCashSize
local function flyBaseCashToHud(parent, sourceLabel, target, onArrived)
	if parent.AbsoluteSize.X == 0 then
		sourceLabel.Visible = false
		onArrived()
		return nil
	end
	local _absolutePosition = sourceLabel.AbsolutePosition
	local _arg0 = sourceLabel.AbsoluteSize / 2
	local srcCenter = _absolutePosition + _arg0
	local absSize = sourceLabel.AbsoluteSize
	local clone = sourceLabel:Clone()
	clone.Name = "EndGameBaseCashFly"
	clone.AnchorPoint = Vector2.new(0.5, 0.5)
	clone.Size = UDim2.new(0, absSize.X, 0, absSize.Y)
	clone.Position = UDim2.new(0, srcCenter.X, 0, srcCenter.Y)
	clone.ZIndex = 32
	clone.Visible = true
	clone.Parent = parent
	-- The clone carries the visual to the HUD; hide the original immediately.
	sourceLabel.Visible = false
	local _absolutePosition_1 = target.AbsolutePosition
	local _arg0_1 = target.AbsoluteSize / 2
	local targetCenter = _absolutePosition_1 + _arg0_1
	local _object = {
		Position = UDim2.new(0, targetCenter.X, 0, targetCenter.Y),
	}
	local _left = "TextSize"
	local _condition = initialBaseCashSize
	if _condition == nil then
		_condition = clone.TextSize
	end
	_object[_left] = _condition
	local fly = TweenService:Create(clone, BASE_CASH_FLY_TI, _object)
	fly.Completed:Connect(function()
		clone:Destroy()
		onArrived()
	end)
	fly:Play()
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
local initialBaseCashColor
local initialMultiplierPosition
local initialMultiplierTransparency
-- ── Cancellation: payout flushed because another popup opened ───────────────────
--
-- Opening any popup while this animation runs drops the finish screen entirely
-- (EndGameButtonModule.flush). The animation must stop where it is and hand back what
-- has NOT reached the HUD yet, so the caller can show it as one floating text.
--
-- Distinct from FloatingCash's rebirth cancellation, which drops the money for good
-- instead of paying out the remainder.
local activeRun
-- Chunk frames live on the ScreenGui, not on the popup frame — hiding the popup does
-- not hide them, so a cancel has to destroy them explicitly.
local FLY_FRAME_NAMES = { "EndGameFloatingChunk", "EndGameBaseCashFly" }
-- Puts the popup labels back to their Studio baseline so the next run starts clean.
local function resetLabels(refs)
	refs.baseCashText.Visible = false
	if initialBaseCashSize ~= nil then
		refs.baseCashText.TextSize = initialBaseCashSize
	end
	if initialBaseCashColor ~= nil then
		refs.baseCashText.TextColor3 = initialBaseCashColor
	end
	refs.multiplierText.Visible = false
	if initialMultiplierPosition ~= nil then
		refs.multiplierText.Position = initialMultiplierPosition
	end
	if initialMultiplierTransparency ~= nil then
		refs.multiplierText.TextTransparency = initialMultiplierTransparency
	end
end
-- Stops a running payout animation and returns what has not been banked yet.
-- Returns undefined when no animation is running (the popup never opened) — the caller
-- then falls back to the full amount the server sent.
local function cancelActiveRun()
	local run = activeRun
	if not run or run.cancelled then
		return nil
	end
	run.cancelled = true
	activeRun = nil
	for _, desc in run.refs.screenGui:GetDescendants() do
		local _name = desc.Name
		if table.find(FLY_FRAME_NAMES, _name) ~= nil then
			desc:Destroy()
		end
	end
	resetLabels(run.refs)
	InformationText:hide()
	return math.max(run.totalEarn - run.banked, 0)
end
-- Runs the full ButtonFinishGame animation, then calls onComplete().
-- Safe to call from a regular task (uses task.wait internally).
local function runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, claimBonus, onComplete)
	local refs = resolveRefs(frame)
	if not refs then
		onComplete()
		return nil
	end
	local _binding = refs
	local multiplierText = _binding.multiplierText
	local baseCashText = _binding.baseCashText
	local screenGui = _binding.screenGui
	-- Snapshot the cancellation generation: a rebirth mid-payout bumps it, and every
	-- deferred callback below bails so no chunk lands in the HUD after the reset to 0.
	local runGen = FloatingCash:current()
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
	-- Le bonus de claim (Perfect ×3 / Critical ×10) grossit la BASE, pas le multiplicateur :
	-- tout ce qui suit part donc de la base boostée — le total payé est identique à
	-- `claimedBaseCash × multiplier` côté serveur.
	local bonus = if claimBonus > 1 then claimBonus else 1
	local boostedBaseCash = baseCash * bonus
	-- Kill penalty applies before the multiplier, so the final payout is known up front —
	-- register it now so a cancel during the very first phases still knows what is owed.
	local effectiveBaseCash = if lossMultiplier < 1 then boostedBaseCash * lossMultiplier else boostedBaseCash
	local effectiveBaseSize = if lossMultiplier < 1 then baseSize * lossMultiplier else baseSize
	local totalEarn = effectiveBaseCash * multiplier
	local run = {
		refs = refs,
		totalEarn = totalEarn,
		banked = 0,
		cancelled = false,
	}
	activeRun = run
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
	-- hold explicite : ce flash SÉQUENCE la suite de l'animation, il garde donc sa
	-- durée courte historique au lieu des ~5 s confortables des autres bandeaux.
	InformationText:show(FINISH_TEXT, {
		holdSeconds = InformationText.HOLD_TIME,
	})
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME)
	if run.cancelled then
		return nil
	end
	-- ── Phase 0: claim bonus — c'est la BASE qui grimpe (×3 Perfect / ×10 Critical) ──
	-- Le multiplicateur affiché ne bouge pas : le bonus se lit ici, sur le base cash qui
	-- compte de sa valeur brute à sa valeur boostée, en doré et gonflé.
	if bonus > 1 then
		-- Bandeau explicite : sans lui, un joueur pourrait croire que c'est le
		-- multiplicateur qui a bougé. Hold court — il ne doit pas traîner sur le paiement.
		InformationText:show(`BASE CASH ×{bonus}`, {
			rarity = "Epic",
			holdSeconds = CLAIM_BONUS_BANNER_HOLD,
		})
		animateCash(baseCashText, baseCash, boostedBaseCash, baseSize, baseSize + CLAIM_BONUS_SIZE_INCREASE, baseColor, CLAIM_BONUS_COLOR, CLAIM_BONUS_TI)
		if run.cancelled then
			return nil
		end
		task.wait(CLAIM_BONUS_HOLD)
		if run.cancelled then
			return nil
		end
		-- Retour à la taille/couleur de base : la phase multiplicateur repart de zéro.
		animateCash(baseCashText, boostedBaseCash, boostedBaseCash, baseSize + CLAIM_BONUS_SIZE_INCREASE, baseSize, CLAIM_BONUS_COLOR, baseColor, CLAIM_BONUS_SETTLE_TI)
		if run.cancelled then
			return nil
		end
	end
	-- ── Kill penalty: shrink BaseCashText value + size before the count-up ────────
	if lossMultiplier < 1 then
		animateCash(baseCashText, boostedBaseCash, effectiveBaseCash, baseSize, effectiveBaseSize, baseColor, baseColor, LOSS_PENALTY_TI)
		if run.cancelled then
			return nil
		end
	end
	-- ── Phase 1: MultiplierText merges into BaseCashText and disappears ───────────
	mergeMultiplierIntoBaseCash(multiplierText, baseCashText)
	if run.cancelled then
		return nil
	end
	-- ── Phase 2: BaseCashText counts up by the in-game multiplier ─────────────────
	-- EffectiveBaseCash already includes every money multiplier (rebirth + tier +
	-- community), so the start number shows the boost — no separate rebirth phase.
	local grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE
	animateCash(baseCashText, effectiveBaseCash, totalEarn, effectiveBaseSize, grownSize, baseColor, BASE_CASH_TARGET_COLOR, BASE_CASH_COUNTUP_TI)
	if run.cancelled then
		return nil
	end
	-- ── Phase 3: spray N floating texts into the money HUD ────────────────────────
	local moneyParent = InGameUIController:getMoneyParent()
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
	-- The run stays "active" (and therefore cancellable) until onComplete actually
	-- fires — a popup opening during the final pause must still cancel it, otherwise
	-- the flush would fall back to the full amount and pay it a second time.
	local complete = function()
		if run.cancelled then
			return nil
		end
		if activeRun == run then
			activeRun = nil
		end
		onComplete()
	end
	-- No HUD target / nothing to spray → deposit visually and finish.
	if not moneyParent or n <= 0 or totalEarn <= 0 then
		if totalEarn > 0 then
			MoneyDisplay:addVisual(totalEarn)
			run.banked = totalEarn
		end
		finishReset()
		complete()
		return nil
	end
	local arrived = 0
	for i = 1, n do
		if run.cancelled then
			return nil
		end
		if FloatingCash:isStale(runGen) then
			break
		end
		local isLast = i == n
		local remaining = if isLast then 0 else totalEarn - i * chunk
		spawnFloatingChunk(screenGui, chunk, baseCashText, moneyParent, {
			onSpawn = function()
				if run.cancelled then
					return nil
				end
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
				if run.cancelled then
					return nil
				end
				if FloatingCash:isStale(runGen) then
					return nil
				end
				MoneyDisplay:addVisual(chunk)
				run.banked += chunk
				arrived += 1
				if arrived >= n then
					finishReset()
					task.delay(0.2, complete)
				end
			end,
		})
		task.wait(FLOATING_TEXT_INTERVAL)
	end
	-- Rebirth broke out of the loop: the money is gone for good, so there is nothing
	-- left to flush — drop the run instead of leaving it cancellable.
	if activeRun == run and FloatingCash:isStale(runGen) then
		activeRun = nil
		finishReset()
	end
end
return {
	cancelActiveRun = cancelActiveRun,
	runEndGameAnimation = runEndGameAnimation,
}
