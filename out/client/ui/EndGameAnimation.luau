-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local MultiplierVisuals = TS.import(script, script.Parent, "MultiplierVisuals").MultiplierVisuals
local InGameUIController = TS.import(script, script.Parent, "InGameUIController").InGameUIController
local MoneyDisplay = TS.import(script, script.Parent, "MoneyDisplay").MoneyDisplay
local FloatingCash = TS.import(script, script.Parent, "FloatingCash").FloatingCash
local InformationText = TS.import(script, script.Parent, "InformationText").InformationText
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
local _MoneyBurst = TS.import(script, script.Parent, "MoneyBurst")
local MONEY_IMAGE = _MoneyBurst.MONEY_IMAGE
local MoneyBurst = _MoneyBurst.MoneyBurst
local _CriticalRain = TS.import(script, script.Parent, "CriticalRain")
local CriticalRain = _CriticalRain.CriticalRain
local RAIN_IMAGE = _CriticalRain.RAIN_IMAGE
local _CashSound = TS.import(script, script.Parent.Parent, "audio", "CashSound")
local playBigPayout = _CashSound.playBigPayout
local playCashSound = _CashSound.playCashSound
local _PayoutTiers = TS.import(script, script.Parent, "PayoutTiers")
local tiersCrossed = _PayoutTiers.tiersCrossed
local topTierIndex = _PayoutTiers.topTierIndex
-- ── ButtonFinishGame payout animation ───────────────────────────────────────────
--
-- Sequence (after the "Finish" flash + optional kill penalty):
--   0.  Claim bonus (Perfect ×3 / Critical ×10, claimBonus > 1): BaseCashText counts up
--       from the raw base to the boosted base with a golden bump — the bonus multiplies
--       the BASE CASH, never the multiplier, and this phase is what shows it.
--   1.  MultiplierText flies into BaseCashText and disappears.
--   2.  BaseCashText counts up by the in-game multiplier, PAR PALIERS (PayoutTiers) :
--       le count-up est découpé en segments qui s'arrêtent pile sur chaque palier
--       franchi, et chaque arrivée déclenche son son + sa gerbe + sa pluie, de plus
--       en plus fort. C'est ce qui rend l'ampleur du gain lisible en temps réel.
--       EffectiveBaseCash already folds in every money multiplier, so no separate
--       rebirth phase is needed.
--   3.  BaseCashText stays put (showing the full total) and sprays N floating texts
--       toward the money HUD; each arrival banks one chunk of the total, avec un
--       pitch qui monte chunk après chunk (crescendo). Le dernier chunk qui atterrit
--       déclenche la gerbe finale sur le compteur.
--
-- `flyBaseCashToHud` / FINAL_MOVE_DELAY décrivent une phase 4 qui n'est PAS branchée :
-- la phase 3 masque déjà le label sur son dernier chunk. Code mort conservé tel quel.
-- ── Tuning ──────────────────────────────────────────────────────────────────────
local FINISH_TEXT = "Finish"
-- Phase 1 — MultiplierText merging into BaseCashText.
local MULTIPLIER_MERGE_TI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Phase 2 — count-up par paliers (PayoutTiers).
-- La durée s'allonge avec le nombre de paliers pour qu'ils aient chacun la place de
-- claquer, mais reste PLAFONNÉE : l'écran de fin ne doit pas traîner sur un gros run.
local COUNTUP_BASE_TIME = 0.6
local COUNTUP_TIME_PER_TIER = 0.2
local COUNTUP_MAX_TIME = 1.2
-- Valeur du compteur : linéaire. Chaque segment est court, et un easing par segment
-- ferait ralentir/repartir le nombre à chaque palier.
local COUNTUP_VALUE_STYLE = Enum.EasingStyle.Linear
-- Taille + couleur : Quad-Out, sur le MÊME temps que la valeur. Pas de dépassement ici
-- — c'est le UIScale qui porte le punch (TextSize est plafonné à 100 par Roblox, un
-- dépassement sur la taille serait écrêté pile sur les gros paliers).
local COUNTUP_STYLE_STYLE = Enum.EasingStyle.Quad
-- Pluie des paliers : bande COURTE (une vague qui passe, pas une averse qui traîne) et
-- plan de rendu BAS — ButtonFinishGame et BaseCashText sont en ZIndex 1, donc la pluie
-- tombe derrière le montant, qui reste lisible.
local TIER_RAIN_BAND = 700
local TIER_RAIN_Z_INDEX = 0
-- Phase 3 — how many floating texts BaseCashText sprays, and how fast.
-- Both tweakable: COUNT splits the total earned into COUNT chunks of
-- totalEarn / COUNT; INTERVAL is the delay between each spawn.
local FLOATING_TEXT_COUNT = 8
local FLOATING_TEXT_INTERVAL = 0.12
-- Plus le run est gros, plus il y a de liasses à encaisser — plafonné pour que la
-- rafale ne s'éternise pas (16 × 0.12 s ≈ 2 s).
local FLOATING_TEXT_PER_TIER = 1
local FLOATING_TEXT_MAX = 16
-- Le pitch du son de dépôt monte de 1 à 1 + CHUNK_PITCH_RISE sur la rafale : les N
-- ka-ching deviennent un arpège au lieu d'une répétition.
local CHUNK_PITCH_RISE = 0.25
-- Gerbe jouée sur le compteur quand la dernière liasse atterrit — le dernier "boum".
local FINAL_BURST_BASE = 10
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
-- BaseCash growth — la TAILLE reste pilotée ici ; la COULEUR, elle, est posée par les
-- paliers (PayoutTiers) et non plus par une cible fixe.
-- 15 et pas plus : Roblox PLAFONNE TextSize à 100 et le label démarre à 85. Au-delà la
-- croissance serait silencieusement écrêtée, et l'agrandissement s'arrêterait au milieu
-- du count-up au lieu de suivre le nombre jusqu'au bout.
local BASE_CASH_MAX_SIZE_INCREASE = 15
-- Punch du palier : le UIScale saute à `tier.punch` puis se recale à 1. Instance
-- SÉPARÉE du label, donc son tween ne croise jamais celui de la taille/couleur et peut
-- se dérouler par-dessus le segment suivant sans le perturber.
local PUNCH_NAME = "EndGamePunch"
local PUNCH_SETTLE_TI = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
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
-- ── Stats du joueur qui calibrent l'escalade ────────────────────────────────────
-- Les paliers sont des CENTILES de la distribution de vol du joueur (PayoutTiers), donc
-- ils dépendent de sa Rocket Speed ET de sa Resistance. Les deux sont des attributs
-- répliqués par PlayerProgressionService — `Resistance` porte déjà la valeur EFFECTIVE
-- (game pass inclus), c'est-à-dire celle que le modèle de risque serveur utilise.
local function playerStat(name, fallback)
	local value = Players.LocalPlayer:GetAttribute(name)
	local _condition = value
	if _condition == nil then
		_condition = fallback
	end
	return _condition
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
local function animateCash(label, startValue, endValue, startSize, endSize, startColor, endColor, ti, styleTi)
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
	local styleTween = TweenService:Create(label, styleTi or ti, {
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
-- ── Phase 2: déclenchement d'un palier ──────────────────────────────────────────
-- UIScale du punch, créé à la demande sous BaseCashText et réutilisé ensuite.
local function getPunchScale(label)
	local existing = label:FindFirstChild(PUNCH_NAME)
	local _result = existing
	if _result ~= nil then
		_result = _result:IsA("UIScale")
	end
	if _result then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = PUNCH_NAME
	scale.Parent = label
	return scale
end
-- Remet le montant à son échelle normale : un punch encore en vol ne doit pas laisser
-- le label gonflé sur l'écran suivant.
local function resetPunchScale(label)
	local existing = label:FindFirstChild(PUNCH_NAME)
	local _result = existing
	if _result ~= nil then
		_result = _result:IsA("UIScale")
	end
	if _result then
		existing.Scale = 1
	end
end
-- Tout ce qu'un palier fait claquer : le son (de plus en plus aigu et fort), la gerbe
-- de billets qui part du montant, et la pluie qui tombe derrière. Les paliers hauts
-- ajoutent le son "gros lot" et une pluie d'or par-dessus la pluie de billets.
local function fireTier(tier, label)
	playCashSound({
		pitch = tier.pitch,
		volume = tier.volume,
	})
	if tier.bigReward then
		playBigPayout()
	end
	-- Saut instantané puis recalage : c'est le "snap" qui se lit comme un impact.
	local punch = getPunchScale(label)
	punch.Scale = tier.punch
	TweenService:Create(punch, PUNCH_SETTLE_TI, {
		Scale = 1,
	}):Play()
	-- Même convention de coordonnées que spawnFloatingChunk : les particules sont
	-- parentées au ScreenGui et positionnées en offsets locaux.
	local _absolutePosition = label.AbsolutePosition
	local _arg0 = label.AbsoluteSize / 2
	local center = _absolutePosition + _arg0
	MoneyBurst:play(center, {
		count = tier.burstCount,
	})
	local rain = {
		count = tier.rainCount,
		band = TIER_RAIN_BAND,
		zIndex = TIER_RAIN_Z_INDEX,
	}
	if tier.ingotDownpour > 0 then
		-- Climax d'une grosse escalade : déluge de lingots à la place des billets. Une
		-- pluie d'or PURE se lit mieux qu'un mélange, et ça tient sous le plafond de
		-- gouttes sans que le déluge ait à évincer sa propre pluie de billets.
		local _object = table.clone(rain)
		setmetatable(_object, nil)
		_object.count = tier.ingotDownpour
		CriticalRain:play(RAIN_IMAGE, _object)
		return nil
	end
	CriticalRain:play(MONEY_IMAGE, rain)
	if tier.goldRain then
		local _object = table.clone(rain)
		setmetatable(_object, nil)
		_object.count = math.floor(tier.rainCount / 2)
		CriticalRain:play(RAIN_IMAGE, _object)
	end
end
-- ── Phase 2: découpage du count-up en segments ──────────────────────────────────
-- Un tween unique regrouperait toutes les détonations au début : les seuils sont
-- géométriques (×100, ×250, ×500) donc l'easing les traverse d'un coup, puis plus rien
-- pendant la moitié de l'animation. On découpe donc le count-up en segments qui
-- s'arrêtent PILE sur la valeur de chaque palier, et on donne à chacun la même durée —
-- l'espacement des détonations est alors régulier par construction.
local function buildSegments(effectiveBaseCash, totalEarn, tiers)
	local immediate = {}
	local segments = {}
	local finalTier
	for _, tier in tiers do
		local value = effectiveBaseCash * tier.threshold
		if value <= effectiveBaseCash then
			-- Seuil déjà atteint au départ (le premier palier vaut ×1) : c'est le coup
			-- d'envoi, il part avec le début du count-up.
			table.insert(immediate, tier)
		elseif value >= totalEarn then
			-- Le palier tombe pile sur le total : c'est l'arrivée finale qui le joue.
			finalTier = tier
		else
			local _arg0 = {
				value = value,
				tier = tier,
			}
			table.insert(segments, _arg0)
		end
	end
	local _arg0 = {
		value = totalEarn,
		tier = finalTier,
	}
	table.insert(segments, _arg0)
	return {
		immediate = immediate,
		segments = segments,
	}
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
	resetPunchScale(refs.baseCashText)
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
-- Les particules de l'escalade vivent sur le ScreenGui, pas sur la popup, et la pluie
-- tient jusqu'à 9 s alors que le paiement dure ~4 s : sans nettoyage explicite elle
-- déborderait sur l'écran suivant.
local function clearTierParticles()
	MoneyBurst:clear()
	CriticalRain:clear()
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
	clearTierParticles()
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
	-- ── Phase 2: count-up par paliers ─────────────────────────────────────────────
	-- EffectiveBaseCash already includes every money multiplier (rebirth + tier +
	-- community), so the start number shows the boost — no separate rebirth phase.
	local grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE
	local rocketSpeed = playerStat("RocketSpeed", 1)
	local resistance = playerStat("Resistance", 0)
	local tiers = tiersCrossed(multiplier, rocketSpeed, resistance)
	local _binding_1 = buildSegments(effectiveBaseCash, totalEarn, tiers)
	local immediate = _binding_1.immediate
	local segments = _binding_1.segments
	local countUpTime = math.min(COUNTUP_BASE_TIME + COUNTUP_TIME_PER_TIER * #tiers, COUNTUP_MAX_TIME)
	local segmentTime = countUpTime / #segments
	local valueTi = TweenInfo.new(segmentTime, COUNTUP_VALUE_STYLE, Enum.EasingDirection.Out)
	local styleTi = TweenInfo.new(segmentTime, COUNTUP_STYLE_STYLE, Enum.EasingDirection.Out)
	-- La taille suit la VALEUR affichée (et non l'index du segment) : le texte grossit
	-- donc au même rythme que le nombre, comme avant le découpage.
	local valueSpan = totalEarn - effectiveBaseCash
	local sizeAt = function(value)
		return if valueSpan > 0 then effectiveBaseSize + (grownSize - effectiveBaseSize) * ((value - effectiveBaseCash) / valueSpan) else grownSize
	end
	-- Coup d'envoi : les paliers déjà atteints à la valeur de départ claquent tout de
	-- suite, sinon le count-up démarrerait en silence.
	local currentColor = baseColor
	for _, tier in immediate do
		fireTier(tier, baseCashText)
		currentColor = tier.color
	end
	baseCashText.TextColor3 = currentColor
	local currentValue = effectiveBaseCash
	local currentSize = effectiveBaseSize
	for _, segment in segments do
		if run.cancelled then
			return nil
		end
		local nextSize = sizeAt(segment.value)
		local _result_2 = segment.tier
		if _result_2 ~= nil then
			_result_2 = _result_2.color
		end
		local _condition_2 = _result_2
		if _condition_2 == nil then
			_condition_2 = currentColor
		end
		local nextColor = _condition_2
		animateCash(baseCashText, currentValue, segment.value, currentSize, nextSize, currentColor, nextColor, valueTi, styleTi)
		if run.cancelled then
			return nil
		end
		currentValue = segment.value
		currentSize = nextSize
		currentColor = nextColor
		if segment.tier then
			fireTier(segment.tier, baseCashText)
		end
	end
	-- Couleur atteinte au sommet de l'escalade : la phase 3 redescend vers `baseColor`
	-- depuis celle-ci, pas depuis une cible fixe.
	local peakColor = currentColor
	-- ── Phase 3: spray N floating texts into the money HUD ────────────────────────
	local moneyParent = InGameUIController:getMoneyParent()
	local topTier = topTierIndex(multiplier, rocketSpeed, resistance)
	local n = math.min(FLOATING_TEXT_COUNT + FLOATING_TEXT_PER_TIER * topTier, FLOATING_TEXT_MAX)
	local chunk = if n > 0 then totalEarn / n else 0
	local finishReset = function()
		-- Leave BaseCashText hidden but reset to the Studio baseline for next run.
		baseCashText.Visible = false
		resetPunchScale(baseCashText)
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
	do
		local i = 1
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i <= n) then
				break
			end
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
					baseCashText.TextColor3 = baseColor:Lerp(peakColor, ratio)
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
					-- Pitch montant sur la rafale : la répétition devient un crescendo.
					local pitch = 1 + (if n > 1 then (arrived / (n - 1)) * CHUNK_PITCH_RISE else 0)
					MoneyDisplay:addVisual(chunk, {
						pitch = pitch,
					})
					run.banked += chunk
					arrived += 1
					if arrived >= n then
						-- Dernier "boum" : une gerbe part du compteur qui vient de tout encaisser.
						local _absolutePosition = moneyParent.AbsolutePosition
						local _arg0 = moneyParent.AbsoluteSize / 2
						local hudCenter = _absolutePosition + _arg0
						MoneyBurst:play(hudCenter, {
							count = FINAL_BURST_BASE + topTier,
						})
						if #tiers > 0 and tiers[#tiers].bigReward then
							playBigPayout()
						end
						finishReset()
						task.delay(0.2, complete)
					end
				end,
			})
			task.wait(FLOATING_TEXT_INTERVAL)
		end
	end
	-- Rebirth broke out of the loop: the money is gone for good, so there is nothing
	-- left to flush — drop the run instead of leaving it cancellable.
	if activeRun == run and FloatingCash:isStale(runGen) then
		activeRun = nil
		finishReset()
		clearTierParticles()
	end
end
return {
	cancelActiveRun = cancelActiveRun,
	runEndGameAnimation = runEndGameAnimation,
}
