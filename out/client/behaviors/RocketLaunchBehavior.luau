-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local MultiplierVisuals = TS.import(script, script.Parent.Parent, "ui", "MultiplierVisuals").MultiplierVisuals
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local EXPLOSION_VIEW_DELAY = _RocketGameConfig.EXPLOSION_VIEW_DELAY
local MULTIPLIER_TICK_RATE = _RocketGameConfig.MULTIPLIER_TICK_RATE
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
local ButtonAnimations = TS.import(script, script.Parent, "ButtonAnimations").ButtonAnimations
local RocketSteerController = TS.import(script, script.Parent, "RocketSteerController").RocketSteerController
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Lighting = _services.Lighting
local Players = _services.Players
local RunService = _services.RunService
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local Workspace = _services.Workspace
-- UI refs — assigned on first setup(), never change after
local claimButton
-- Les deux dégradés du ClaimButton : "Claim" pendant le vol, "Home" une fois le gain
-- verrouillé. On ne bascule de l'un à l'autre qu'au réarmement "Go Home" (quand la
-- couleur du bouton redevient normale), pas pendant l'assombrissement du claim.
local claimGradient
local homeGradient
-- Le libellé posé sur le ClaimButton : "Claim" pendant le vol, "Go Home" une fois le
-- gain verrouillé (le bouton se réarme alors pour rentrer à la base).
local claimLabel
local claimLabelOriginalText
local multiplierText
local resultMultiplierText
-- Popup "gain verrouillé" révélé au claim : CanvasGroup (fade) + Frame qui monte.
local claimPopupGroup
local claimPopup
local claimPopupResult
local claimPopupOriginalPos
local claimPopupRevealId = 0
local claimPopupWarmed = false
local buttonOriginalSize
local claimButtonOriginalColor
local multiplierTextOriginalSize
local multiplierTextOriginalColor
-- Pulse d'onboarding du bouton Claim : tant que le joueur n'a pas encaissé quelques
-- fois, le bouton respire (taille + halo) pour que le geste soit impossible à rater.
-- Compteur en mémoire, remis à zéro à chaque session — aucun état serveur.
local claimPulseTween
local claimPulseStroke
local claimPulseStrokeTween
local sessionClaimCount = 0
-- Pendant le tutorial c'est lui qui met le bouton Claim en avant (TutorialFocus) : deux
-- animations concurrentes sur le même bouton se battraient.
local tutorialActive = false
-- Lighting effects — created once in init()
local bloomEffect
-- Per-game state
local isGameActive = false
local hasClaimed = false
local isGoHomeMode = false
local runId = 0
local multiplierTextSize = 0
-- Aperçu live du gain "si je claim maintenant" (floor(EffectiveBaseCash × multiplicateur)).
local resultBaseCash = 100
local lastResultMultiplier = STARTING_MULTIPLIER
local resultUpdateElapsed = 0
local shakeAmplitude = 0
-- Continuous multiplier display: the server sends a discrete value each tick; we
-- lerp the shown number from the previous value to the new one over the tick so it
-- passes through every intermediate number (1.01, 1.02, …) instead of jumping.
local displayedMultiplier = STARTING_MULTIPLIER
local multiplierFrom = STARTING_MULTIPLIER
local multiplierTo = STARTING_MULTIPLIER
local multiplierElapsed = 0
local shakeUndoCFrame
local baseFov = 70
local activatedConn
-- Bascule musicale à l'altitude : on capture le Y de la fusée au décollage, puis une fois
-- qu'elle a grimpé HIGH_ALTITUDE_MUSIC_THRESHOLD studs, on crossfade la BGM vers la piste
-- haute altitude (une seule fois par run). Pendant un run la caméra suit la fusée, donc son
-- CameraSubject EST la part de la fusée : on lit son Y en direct, sans plomberie réseau.
local HIGH_ALTITUDE_MUSIC_THRESHOLD = 65
local rocketMusicSubject
local rocketBaselineY = 0
local highAltitudeReached = false
-- Son de cash joué au moment du claim (au lieu du clic UI générique — le ClaimButton
-- porte l'attribut NoUiClick pour que UiClickSound le saute). Template préchargé, cloné
-- à chaque claim pour éviter tout fetch CDN.
local claimCashSoundTemplate = (function()
	local sound = Instance.new("Sound")
	sound.Name = "ClaimCashSoundTemplate"
	sound.SoundId = AudioConfig.sfx.moneyGain.id
	sound.Volume = AudioConfig.sfx.moneyGain.volume
	sound.Parent = SoundService
	return sound
end)()
local function playClaimCashSound()
	local sound = claimCashSoundTemplate:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
end
-- Position "en bas" du popup : sa position d'origine décalée de CLAIM_POPUP_RISE px vers le bas.
local CLAIM_POPUP_RISE
local function claimPopupLoweredPos()
	local p = claimPopupOriginalPos or UDim2.new()
	return UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + CLAIM_POPUP_RISE)
end
-- Pré-chauffage : un CanvasGroup n'alloue sa texture interne qu'à son premier rendu
-- (GroupTransparency < 1) ; cette première frame est basse résolution → reveal flou. On force
-- donc un rendu invisible-à-l'oeil (0.99 = 1% d'opacité) au démarrage pour allouer la texture,
-- puis on recoupe le rendu (retour à 1) : aucun coût permanent. Fait une seule fois par session.
local function warmUpClaimPopup()
	if claimPopupWarmed or not claimPopupGroup then
		return nil
	end
	claimPopupWarmed = true
	local group = claimPopupGroup
	local id = claimPopupRevealId
	group.GroupTransparency = 0.99
	task.delay(0.3, function()
		-- Si rien ne s'est affiché entre-temps (id inchangé), on coupe le rendu.
		if id == claimPopupRevealId then
			group.GroupTransparency = 1
		end
	end)
end
-- État de repos : popup invisible (fade complet) et abaissé, prêt à monter au claim.
-- Bump du jeton pour qu'un timer de disparition en attente ne touche pas un futur reveal.
local function hideClaimPopup()
	claimPopupRevealId += 1
	if claimPopupGroup then
		claimPopupGroup.GroupTransparency = 1
	end
	if claimPopup then
		claimPopup.Position = claimPopupLoweredPos()
	end
end
-- Reveal au claim : on écrit le gain verrouillé, fondu entrant + montée, puis après
-- CLAIM_POPUP_HOLD s le popup se refond (fade out) — sauf si un reset/reveal l'a invalidé.
local ClaimPopupTI, CLAIM_POPUP_HOLD, ClaimPopupFadeTI
local function revealClaimPopup(amount)
	if not claimPopupGroup or not claimPopup or not claimPopupResult or not claimPopupOriginalPos then
		return nil
	end
	claimPopupRevealId += 1
	local myId = claimPopupRevealId
	claimPopupResult.Text = `${FormatNumber(amount)}`
	-- Repart de l'état de repos avant d'animer (au cas où un tween précédent traînerait).
	claimPopupGroup.GroupTransparency = 1
	claimPopup.Position = claimPopupLoweredPos()
	TweenService:Create(claimPopupGroup, ClaimPopupTI, {
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(claimPopup, ClaimPopupTI, {
		Position = claimPopupOriginalPos,
	}):Play()
	task.delay(CLAIM_POPUP_HOLD, function()
		if myId ~= claimPopupRevealId or not claimPopupGroup then
			return nil
		end
		TweenService:Create(claimPopupGroup, ClaimPopupFadeTI, {
			GroupTransparency = 1,
		}):Play()
	end)
end
-- Live multiplier label text. 2 decimals below 100 ("1.00", "1.05") so the slow
-- early climb is readable, 1 decimal below 1000, then k/M/B suffixes so long holds
-- don't overflow the label.
local function formatMultiplier(value)
	if value < 100 then
		return string.format("%.2f", value)
	end
	if value < 1000 then
		return string.format("%.1f", value)
	end
	return FormatNumber(value)
end
local SIZE_GROWTH_PER_UPDATE = 4
local MAX_MULTIPLIER_SIZE_INCREASE = 80
local MAX_SHAKE_AMPLITUDE = 0.06
-- Tremblement du décollage : fort au début (poussée/atmosphère) puis s'atténue vers 0
-- (on monte vers l'espace, c'est de plus en plus calme).
local LAUNCH_SHAKE_START = 0.06
local LAUNCH_SHAKE_DECAY = 0.6
local MAX_BLOOM_INTENSITY = 1.5
-- Couleur du ClaimButton quand la fusée explose (il ne disparaît plus, il rougit).
-- Aussi appliquée au claim : le bouton devient rouge dès qu'on verrouille.
local CLAIM_BUTTON_EXPLODE_COLOR = Color3.fromRGB(200, 45, 45)
-- Après un claim le bouton se réarme en "Go Home" : court délai anti-double-clic, puis il
-- redevient cliquable pour rentrer à la base (fusée stoppée, caméra rendue au joueur).
local CLAIM_REARM_DELAY = 0.6
local GO_HOME_LABEL = "Go Home"
-- Nombre de claims après lequel le pulse d'onboarding s'arrête définitivement (session).
local CLAIM_PULSE_RUNS = 3
-- Amplitude du gonflement du bouton pendant le pulse.
local CLAIM_PULSE_SCALE = 1.08
local ClaimPulseTI = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- Aperçu de gain : on ne rafraîchit le texte que si le multiplicateur a bougé d'au moins
-- RESULT_UPDATE_MULT_STEP ET qu'au moins RESULT_UPDATE_MIN_DELAY s'est écoulé (anti-spam).
local RESULT_UPDATE_MULT_STEP = 0.01
local RESULT_UPDATE_MIN_DELAY = 0.2
local UpgradeMultiplayerTI = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PostProcessTI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ResetPostProcessTI = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ZoomResetTI = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXPLODE_FOV_OVERSHOOT = 18
-- Reveal du popup de gain au claim : le popup part un peu plus bas et transparent, puis
-- monte de CLAIM_POPUP_RISE px en fondu (fade via CanvasGroup) jusqu'à sa position d'origine.
CLAIM_POPUP_RISE = 45
CLAIM_POPUP_HOLD = 3
ClaimPopupTI = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
ClaimPopupFadeTI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local function resetPostProcess(instant)
	if instant == nil then
		instant = false
	end
	local ti = if instant then TweenInfo.new(0) else ResetPostProcessTI
	if bloomEffect then
		TweenService:Create(bloomEffect, ti, {
			Intensity = 0,
		}):Play()
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local fovTi = if instant then TweenInfo.new(0) else ZoomResetTI
		TweenService:Create(camera, fovTi, {
			FieldOfView = baseFov,
		}):Play()
	end
	shakeAmplitude = 0
end
local stopClaimPulse
local function setTutorialActive(active)
	tutorialActive = active
	if active then
		stopClaimPulse()
	end
end
-- Called once at startup — all event listeners live here, gated by isGameActive
local function init()
	-- Précharge le son de cash pour que même le TOUT premier claim de la session soit
	-- instantané (les suivants sont déjà en cache). 100 % client : aucune latence réseau.
	task.spawn(function()
		pcall(function()
			return ContentProvider:PreloadAsync({ claimCashSoundTemplate })
		end)
	end)
	-- Comptage continu du multiplier : on interpole le nombre affiché de l'ancienne
	-- valeur vers la nouvelle sur la durée d'un tick, donc il passe par tous les
	-- nombres intermédiaires (lent au début, de plus en plus vite).
	RunService.RenderStepped:Connect(function(dt)
		if not isGameActive or not multiplierText then
			return nil
		end
		-- Une fois la fusée montée de HIGH_ALTITUDE_MUSIC_THRESHOLD studs au-dessus du pad,
		-- on crossfade vers la piste haute altitude (une seule fois par run).
		if rocketMusicSubject and not highAltitudeReached and rocketMusicSubject.Position.Y - rocketBaselineY >= HIGH_ALTITUDE_MUSIC_THRESHOLD then
			highAltitudeReached = true
			MusicController:enterHighAltitude()
		end
		if multiplierElapsed < MULTIPLIER_TICK_RATE then
			multiplierElapsed = math.min(multiplierElapsed + dt, MULTIPLIER_TICK_RATE)
			local a = multiplierElapsed / MULTIPLIER_TICK_RATE
			displayedMultiplier = multiplierFrom + (multiplierTo - multiplierFrom) * a
		else
			displayedMultiplier = multiplierTo
		end
		multiplierText.Text = `{formatMultiplier(displayedMultiplier)}x`
		-- Aperçu live du gain "si je claim maintenant" : floor(EffectiveBaseCash × mult).
		-- Rafraîchi seulement quand le multiplicateur a bougé d'au moins RESULT_UPDATE_MULT_STEP
		-- ET qu'au moins RESULT_UPDATE_MIN_DELAY s'est écoulé. Figé une fois qu'on a claim.
		if resultMultiplierText and not hasClaimed then
			resultUpdateElapsed += dt
			if resultUpdateElapsed >= RESULT_UPDATE_MIN_DELAY and math.abs(displayedMultiplier - lastResultMultiplier) >= RESULT_UPDATE_MULT_STEP then
				lastResultMultiplier = displayedMultiplier
				resultUpdateElapsed = 0
				resultMultiplierText.Text = `${FormatNumber(math.floor(resultBaseCash * displayedMultiplier))}`
			end
		end
		-- Le tremblement de décollage s'atténue avec le temps (fort au début → calme).
		shakeAmplitude = shakeAmplitude * math.max(0, 1 - LAUNCH_SHAKE_DECAY * dt)
	end)
	bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Name = "HoldOrDropBloom"
	bloomEffect.Intensity = 0
	bloomEffect.Size = 24
	bloomEffect.Threshold = 0.95
	bloomEffect.Parent = Lighting
	-- ── Camera shake — two-binding design ────────────────────────────────────────
	-- Problem: Roblox's default camera in Custom mode uses an internal spring that
	-- may read camera.CFrame as its starting point each tick. If we only apply shake
	-- AFTER the Roblox camera update, the shaken CFrame bleeds into the spring state
	-- of the next frame → the "base" look direction drifts over time.
	--
	-- Fix: bind at Camera-1 to RESTORE the clean CFrame before Roblox's camera runs,
	-- so its spring always starts from an unshaken base. Then bind at Camera+1 to save
	-- that clean CFrame and apply a fresh shake offset.
	--
	-- new CFrame(pos, lookAt) forces world-up orientation → no roll accumulation.
	RunService:BindToRenderStep("HoldOrDropShakeUndo", Enum.RenderPriority.Camera.Value - 1, function()
		if not shakeUndoCFrame then
			return nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CFrame = shakeUndoCFrame
		end
		shakeUndoCFrame = nil
	end)
	RunService:BindToRenderStep("HoldOrDropShake", Enum.RenderPriority.Camera.Value + 1, function()
		if shakeAmplitude <= 0 then
			shakeUndoCFrame = nil
			return nil
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return nil
		end
		local cf = camera.CFrame
		shakeUndoCFrame = cf
		local _lookVector = cf.LookVector
		local _rightVector = cf.RightVector
		local _arg0 = (math.random() - 0.5) * shakeAmplitude
		local _upVector = cf.UpVector
		local _arg0_1 = (math.random() - 0.5) * shakeAmplitude
		local newLookDir = _lookVector + (_rightVector * _arg0) + (_upVector * _arg0_1)
		camera.CFrame = CFrame.new(cf.Position, cf.Position + newLookDir)
	end)
	Events.PlayerKilledEvent.OnClientEvent:Connect(function()
		-- La fusée explose (le joueur ne meurt plus). Le bouton "claim" ne disparaît
		-- pas : il devient rouge et non-cliquable (remis à l'état normal au lancement).
		-- Fin de partie : la fusée n'existe plus → on stoppe la montée du multiplierText
		-- (vrai aussi bien après un claim qu'après une perte).
		isGameActive = false
		isGoHomeMode = false
		stopClaimPulse()
		RocketSteerController:stop()
		MusicController:stopRunMusic()
		local _result = activatedConn
		if _result ~= nil then
			_result:Disconnect()
		end
		activatedConn = nil
		if claimButton then
			claimButton.Active = false
			claimButton.Interactable = false
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR
		end
		-- La caméra orbitale reste sur la fusée qui explose un court instant — punch FOV
		-- + shake d'impact — puis revient au joueur. Le son d'explosion vient du serveur.
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = baseFov + EXPLODE_FOV_OVERSHOOT
			TweenService:Create(camera, ZoomResetTI, {
				FieldOfView = baseFov,
			}):Play()
		end
		-- Shake d'impact qui s'atténue rapidement
		shakeAmplitude = MAX_SHAKE_AMPLITUDE * 1.6
		task.spawn(function()
			for i = 0, 15 do
				task.wait(0.03)
				shakeAmplitude *= 0.85
			end
			shakeAmplitude = 0
		end)
		-- On attend que l'explosion se joue avant de ramener la caméra au joueur.
		task.delay(EXPLOSION_VIEW_DELAY, function()
			local cam = Workspace.CurrentCamera
			if cam then
				cam.FieldOfView = baseFov
			end
			CameraController.BringBackPlayerCamera()
		end)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = baseFov
		end
	end)
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		-- The HUD stays hidden until the EndGameButton (ButtonFinishGame) opens —
		-- EndGameButtonBehavior re-enables it on EndGameStartEvent.
		-- Safety net: stop the held pose if the game ended on explosion.
		-- After a claim the loop is already stopped, so this is a no-op.
		isGameActive = false
		RocketSteerController:stop()
		ButtonAnimations.stop()
		-- Fin sans explosion (cas défensif) : la caméra n'a pas été ramenée par
		-- PlayerKilledEvent, on la rend au joueur ici.
		if not exploded then
			CameraController.BringBackPlayerCamera()
		end
		print(`Game over — exploded: {exploded} | cash: {cashEarned} | {multiplier}x`)
	end)
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		if not isGameActive or not multiplierText then
			return nil
		end
		-- Nouvelle cible : le nombre affiché va monter en continu vers `multiplier`
		-- sur la durée d'un tick (voir la boucle RenderStepped dans init).
		multiplierFrom = displayedMultiplier
		multiplierTo = multiplier
		multiplierElapsed = 0
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE
		local _exp = multiplierTextSize
		local _condition = multiplierTextOriginalSize
		if _condition == nil then
			_condition = 0
		end
		local factor = math.clamp((_exp - _condition) / MAX_MULTIPLIER_SIZE_INCREASE, 0, 1)
		local capturedColor = (multiplierTextOriginalColor or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 0, 0), factor)
		-- Snapshot pour la popup de fin (taille + couleur au moment de la fin)
		MultiplierVisuals:capture(multiplierTextSize, capturedColor)
		-- Bump de taille + virage au rouge (la valeur, elle, monte en continu)
		TweenService:Create(multiplierText, UpgradeMultiplayerTI, {
			TextSize = multiplierTextSize,
			TextColor3 = capturedColor,
		}):Play()
		-- Effets ambiants : pas de vignette/teinte rouge ni de zoom FOV progressif pendant
		-- le décollage ; juste un léger bloom. Le tremblement est géré (et atténué) dans la
		-- boucle RenderStepped, pas ici.
		if bloomEffect then
			TweenService:Create(bloomEffect, PostProcessTI, {
				Intensity = factor * MAX_BLOOM_INTENSITY,
			}):Play()
		end
	end)
	-- Claim confirmé par le serveur : on FIGE le gain verrouillé EXACT (= payout serveur,
	-- floor(EffectiveBaseCash × claimedMultiplier)). Mise à jour immédiate, sans throttle.
	-- La fusée continue et le multiplierText grimpe encore, mais ce texte reste figé.
	Events.ClaimAcceptedEvent.OnClientEvent:Connect(function(claimedMultiplier)
		local claimedCash = math.floor(resultBaseCash * claimedMultiplier)
		if resultMultiplierText then
			resultMultiplierText.Text = `${FormatNumber(claimedCash)}`
			resultMultiplierText.Visible = true
		end
		-- Popup de gain verrouillé : fondu entrant + montée avec le montant exact.
		revealClaimPopup(claimedCash)
	end)
	-- La fusée explose sans claim : la partie est finie côté client (le claim ne peut
	-- plus rien verrouiller). PlayerKilledEvent, qui suit immédiatement, gère la caméra,
	-- le shake et l'état du bouton — ici on coupe juste la musique et le bloom.
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		if not isGameActive then
			return nil
		end
		isGameActive = false
		MusicController:stopRunMusic()
		if bloomEffect then
			bloomEffect.Intensity = 0
		end
	end)
end
-- Arrête le pulse et remet le bouton à sa taille / son halo d'origine. Idempotent :
-- appelable même si aucun pulse ne tourne.
function stopClaimPulse()
	local _result = claimPulseTween
	if _result ~= nil then
		_result:Cancel()
	end
	claimPulseTween = nil
	local _result_1 = claimPulseStrokeTween
	if _result_1 ~= nil then
		_result_1:Cancel()
	end
	claimPulseStrokeTween = nil
	if claimPulseStroke then
		claimPulseStroke.Enabled = false
	end
	if claimButton and buttonOriginalSize then
		claimButton.Size = buttonOriginalSize
	end
end
-- Fait respirer le bouton tant que le joueur n'a pas encaissé CLAIM_PULSE_RUNS fois.
-- À appeler APRÈS la restauration de claimButton.Size dans setup(), sinon la taille
-- d'origine serait écrasée par une frame de pulse.
local function startClaimPulse()
	if tutorialActive then
		return nil
	end
	if sessionClaimCount >= CLAIM_PULSE_RUNS then
		return nil
	end
	if not claimButton or not buttonOriginalSize then
		return nil
	end
	-- Halo créé une seule fois, en code — rien à ajouter dans Studio.
	if not claimPulseStroke then
		local stroke = Instance.new("UIStroke")
		stroke.Name = "ClaimPulseStroke"
		stroke.Thickness = 4
		stroke.Color = Color3.new(1, 1, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = claimButton
		claimPulseStroke = stroke
	end
	claimPulseStroke.Enabled = true
	claimPulseStroke.Transparency = 0.8
	local s = buttonOriginalSize
	local grown = UDim2.new(s.X.Scale * CLAIM_PULSE_SCALE, s.X.Offset * CLAIM_PULSE_SCALE, s.Y.Scale * CLAIM_PULSE_SCALE, s.Y.Offset * CLAIM_PULSE_SCALE)
	claimPulseTween = TweenService:Create(claimButton, ClaimPulseTI, {
		Size = grown,
	})
	claimPulseTween:Play()
	claimPulseStrokeTween = TweenService:Create(claimPulseStroke, ClaimPulseTI, {
		Transparency = 0.1,
	})
	claimPulseStrokeTween:Play()
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(inGameUI)
	local popup = inGameUI:WaitForChild("RocketLaunch")
	local claimButtonFrame = popup:WaitForChild("ClaimButtonFrame")
	claimButton = claimButtonFrame:WaitForChild("ClaimButton")
	claimGradient = claimButton:WaitForChild("UIGradientClaim")
	homeGradient = claimButton:WaitForChild("UIGradientHome")
	claimLabel = claimButtonFrame:WaitForChild("TextLabel")
	multiplierText = popup:WaitForChild("MultiplierText")
	resultMultiplierText = popup:WaitForChild("ResultMultiplierText")
	-- Popup de gain (fade + montée) révélé au claim.
	claimPopupGroup = popup:WaitForChild("CanvasGroup")
	claimPopup = claimPopupGroup:WaitForChild("ClaimButtonPopup")
	claimPopupResult = claimPopup:WaitForChild("ResultText")
	if not claimPopupOriginalPos then
		claimPopupOriginalPos = claimPopup.Position
	end
	-- Le ClaimButton joue son propre son (cash) au clic → on demande à UiClickSound de
	-- sauter le clic générique pour ce bouton (attribut lu au moment du clic).
	claimButton:SetAttribute("NoUiClick", true)
	-- Save original sizes/colors on first run so we can restore each game
	if not buttonOriginalSize then
		buttonOriginalSize = claimButton.Size
	end
	if not (claimLabelOriginalText ~= "" and claimLabelOriginalText) then
		claimLabelOriginalText = claimLabel.Text
	end
	if not claimButtonOriginalColor then
		claimButtonOriginalColor = claimButton.BackgroundColor3
	end
	if not (multiplierTextOriginalSize ~= 0 and multiplierTextOriginalSize == multiplierTextOriginalSize and multiplierTextOriginalSize) then
		multiplierTextOriginalSize = multiplierText.TextSize
	end
	if not multiplierTextOriginalColor then
		multiplierTextOriginalColor = multiplierText.TextColor3
	end
	-- Reset per-game state
	local _result = Workspace.CurrentCamera
	if _result ~= nil then
		_result = _result.FieldOfView
	end
	local _condition = _result
	if _condition == nil then
		_condition = 70
	end
	baseFov = _condition
	isGameActive = true
	hasClaimed = false
	isGoHomeMode = false
	runId += 1
	claimLabel.Text = claimLabelOriginalText
	-- EffectiveBaseCash (attribut répliqué) : base du gain affiché dans ResultMultiplierText.
	-- Lu une fois par partie — comme côté serveur, il ne bouge pas en cours de hold.
	local _condition_1 = (Players.LocalPlayer:GetAttribute("EffectiveBaseCash"))
	if _condition_1 == nil then
		_condition_1 = 100
	end
	resultBaseCash = _condition_1
	lastResultMultiplier = STARTING_MULTIPLIER
	resultUpdateElapsed = 0
	-- Bascule musicale à l'altitude : baseline = Y de la fusée maintenant (encore sur le pad).
	-- La caméra suit déjà la fusée (StartOrbit), donc son CameraSubject EST la part de la fusée ;
	-- on lit son Y en direct dans la boucle RenderStepped pour détecter le seuil.
	highAltitudeReached = false
	local _camSubject = Workspace.CurrentCamera
	if _camSubject ~= nil then
		_camSubject = _camSubject.CameraSubject
	end
	local camSubject = _camSubject
	if camSubject and camSubject:IsA("BasePart") then
		rocketMusicSubject = camSubject
		rocketBaselineY = camSubject.Position.Y
	else
		rocketMusicSubject = nil
	end
	MusicController:startRun()
	ButtonAnimations.playHold()
	RocketSteerController:start()
	multiplierText.TextSize = multiplierTextOriginalSize
	multiplierText.TextColor3 = multiplierTextOriginalColor
	multiplierTextSize = multiplierTextOriginalSize
	-- Le compteur continu redémarre à 1.00x.
	displayedMultiplier = STARTING_MULTIPLIER
	multiplierFrom = STARTING_MULTIPLIER
	multiplierTo = STARTING_MULTIPLIER
	multiplierElapsed = MULTIPLIER_TICK_RATE
	MultiplierVisuals:clear()
	resetPostProcess(true)
	-- Décollage : gros tremblement au départ, atténué ensuite par la boucle RenderStepped.
	shakeAmplitude = LAUNCH_SHAKE_START
	-- Restore button to full size, normal colour and re-enable it
	claimButton.Size = buttonOriginalSize
	claimButton.BackgroundColor3 = claimButtonOriginalColor
	claimButton.Interactable = true
	claimButton.Active = true
	claimButton.Visible = true
	-- Décollage : le bouton repart avec le dégradé "Claim" (le dégradé "Home" ne réapparaîtra
	-- qu'au réarmement Go Home).
	if claimGradient then
		claimGradient.Enabled = true
	end
	if homeGradient then
		homeGradient.Enabled = false
	end
	-- Onboarding : le bouton respire tant que le joueur n'a pas encaissé quelques fois.
	-- Doit venir APRÈS la restauration de Size ci-dessus.
	stopClaimPulse()
	startClaimPulse()
	-- Aperçu de gain visible dès le décollage : "si je claim maintenant" = baseCash × 1.00x.
	-- Il grimpe ensuite (throttlé) dans la boucle RenderStepped, puis se fige au claim.
	resultMultiplierText.Text = `${FormatNumber(math.floor(resultBaseCash * STARTING_MULTIPLIER))}`
	resultMultiplierText.Visible = true
	-- Popup de gain caché tant qu'on n'a pas claim (fade complet + abaissé).
	hideClaimPopup()
	-- Pré-chauffe la texture du CanvasGroup (une seule fois) pour éviter un premier reveal flou.
	warmUpClaimPopup()
	-- Reset UI
	multiplierText.Text = `{formatMultiplier(STARTING_MULTIPLIER)}x`
	-- Clean up any leftover connections from a previous game
	local _result_1 = activatedConn
	if _result_1 ~= nil then
		_result_1:Disconnect()
	end
	-- Claim : le joueur VERROUILLE son multiplicateur. La partie NE s'arrête PAS —
	-- la fusée continue de monter (le multiplierText grimpe encore) jusqu'à l'explosion.
	-- Le bouton devient rouge (comme à l'explosion) et non-cliquable (pas de double claim) ;
	-- on joue le son de cash ; le serveur renvoie la valeur verrouillée exacte via
	-- ClaimAcceptedEvent (figée dans ResultMultiplierText).
	local fireClaim = function()
		if not isGameActive or hasClaimed then
			return nil
		end
		hasClaimed = true
		sessionClaimCount += 1
		stopClaimPulse()
		if claimButton then
			claimButton.Active = false
			claimButton.Interactable = false
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR
		end
		playClaimCashSound()
		Events.ClaimButtonEvent:FireServer()
		-- Le bouton se réarme après CLAIM_REARM_DELAY, cette fois en "Go Home" : le gain
		-- est verrouillé, le joueur peut rentrer à la base au lieu d'attendre l'explosion.
		-- Annulé si la partie s'est terminée entre-temps (explosion) ou si une nouvelle
		-- partie a démarré (runId).
		-- PAS pendant le tutorial : le step claim-explode veut MONTRER l'explosion, et un
		-- bouton "Go Home" rallumé (mais bloqué par TutorialGate) ne ferait qu'inviter à un
		-- clic sans effet. Le bouton reste donc éteint, tel que le claim l'a laissé.
		if tutorialActive then
			return nil
		end
		local myRun = runId
		task.delay(CLAIM_REARM_DELAY, function()
			if myRun ~= runId or not isGameActive or not claimButton then
				return nil
			end
			isGoHomeMode = true
			if claimLabel then
				claimLabel.Text = GO_HOME_LABEL
			end
			-- Retour à la couleur d'origine : le rouge signale "non cliquable", or le
			-- bouton redevient bien cliquable (cette fois pour rentrer à la base). C'est à
			-- cet instant précis — pas pendant l'assombrissement du claim — qu'on bascule
			-- du dégradé "Claim" vers le dégradé "Home".
			if claimButtonOriginalColor then
				claimButton.BackgroundColor3 = claimButtonOriginalColor
			end
			if claimGradient then
				claimGradient.Enabled = false
			end
			if homeGradient then
				homeGradient.Enabled = true
			end
			claimButton.Active = true
			claimButton.Interactable = true
		end)
	end
	-- Retour à la base : la fusée s'arrête et la caméra revient au joueur, exactement
	-- comme après une explosion — c'est le serveur qui clôt la partie (GameResultEvent
	-- avec exploded=false → CameraController.BringBackPlayerCamera).
	local fireGoHome = function()
		if not isGameActive or not isGoHomeMode then
			return nil
		end
		isGoHomeMode = false
		stopClaimPulse()
		if claimButton then
			claimButton.Active = false
			claimButton.Interactable = false
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR
		end
		MusicController:stopRunMusic()
		RocketSteerController:stop()
		-- On coupe TOUS les effets de vol d'un coup : tremblement de caméra, bloom et FOV.
		-- Indispensable ici : la boucle RenderStepped qui atténue le tremblement ne tourne
		-- que tant que la partie est active, donc un reste de shake serait figé sur la
		-- caméra une fois rendue au joueur (l'explosion, elle, a sa propre extinction).
		resetPostProcess(true)
		Events.GoHomeEvent:FireServer()
	end
	activatedConn = claimButton.Activated:Connect(function()
		if isGoHomeMode then
			fireGoHome()
		else
			fireClaim()
		end
	end)
end
return {
	setTutorialActive = setTutorialActive,
	init = init,
	setup = setup,
}
