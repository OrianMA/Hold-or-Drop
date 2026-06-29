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
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Lighting = _services.Lighting
local Players = _services.Players
local RunService = _services.RunService
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
local Workspace = _services.Workspace
-- UI refs — assigned on first setup(), never change after
local claimButton
local multiplierText
local buttonOriginalSize
local claimButtonOriginalColor
local multiplierTextOriginalSize
local multiplierTextOriginalColor
-- Lighting effects — created once in init()
local bloomEffect
-- Per-game state
local isGameActive = false
local released = false
local multiplierTextSize = 0
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
local spaceConn
local activatedConn
local parryKnockbackCamConn
-- Son de parry — id centralisé dans AudioConfig.
local SOUND_PARRY_ID = AudioConfig.sfx.parry.id
-- Template persistant en SoundService : le client garde l'asset en mémoire dès le démarrage.
-- Cloner ce template au moment du parry élimine le fetch CDN et le délai de buffering.
local parrySoundTemplate = (function()
	local sound = Instance.new("Sound")
	sound.Name = "ParrySoundTemplate"
	sound.SoundId = SOUND_PARRY_ID
	sound.Volume = AudioConfig.sfx.parry.volume
	sound.Parent = SoundService
	return sound
end)()
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
local CLAIM_BUTTON_EXPLODE_COLOR = Color3.fromRGB(200, 45, 45)
local UpgradeMultiplayerTI = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ReleaseButtonDesapearTI = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PostProcessTI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ResetPostProcessTI = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ZoomResetTI = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ExplodeFovPunchTI = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXPLODE_FOV_OVERSHOOT = 18
local PerfectParrytime = 2
local function resetPostProcess(instant, explode)
	if instant == nil then
		instant = false
	end
	if explode == nil then
		explode = false
	end
	local ti = if instant or explode then TweenInfo.new(0) else ResetPostProcessTI
	if bloomEffect then
		TweenService:Create(bloomEffect, ti, {
			Intensity = 0,
		}):Play()
	end
	local camera = Workspace.CurrentCamera
	if camera then
		if explode then
			TweenService:Create(camera, ExplodeFovPunchTI, {
				FieldOfView = baseFov + EXPLODE_FOV_OVERSHOOT,
			}):Play()
		else
			local fovTi = if instant then TweenInfo.new(0) else ZoomResetTI
			TweenService:Create(camera, fovTi, {
				FieldOfView = baseFov,
			}):Play()
		end
	end
	shakeAmplitude = 0
end
local function endInput()
	isGameActive = false
	released = true
	MusicController:stopButtonMusic()
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	spaceConn = nil
	resetPostProcess()
	if claimButton then
		claimButton.Active = false
		local tween = TweenService:Create(claimButton, ReleaseButtonDesapearTI, {
			Size = UDim2.new(0, 0, 0, 0),
		})
		tween:Play()
		tween.Completed:Wait()
		claimButton.Visible = false
	end
end
local function startParryWindow()
	isGameActive = false
	resetPostProcess(false, true)
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	spaceConn = nil
	local _result_1 = activatedConn
	if _result_1 ~= nil then
		_result_1:Disconnect()
	end
	activatedConn = nil
	if not claimButton then
		released = true
		return nil
	end
	-- Le bouton reste visible pendant la fenêtre de parry (il peut servir à parer).
	claimButton.Active = true
	local fireParry = function()
		if released then
			return nil
		end
		released = true
		local _result_2 = spaceConn
		if _result_2 ~= nil then
			_result_2:Disconnect()
		end
		spaceConn = nil
		local _result_3 = activatedConn
		if _result_3 ~= nil then
			_result_3:Disconnect()
		end
		activatedConn = nil
		print("perfect parry")
		Events.PerfectParryEvent:FireServer()
	end
	spaceConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return nil
		end
		if input.KeyCode == Enum.KeyCode.Space then
			fireParry()
		end
	end)
	activatedConn = claimButton.Activated:Connect(fireParry)
	-- Fin de la fenêtre de parry — le bouton reste visible (rougi par PlayerKilledEvent
	-- si la partie est perdue), on coupe juste l'input de parry.
	task.delay(PerfectParrytime, function()
		local _result_2 = spaceConn
		if _result_2 ~= nil then
			_result_2:Disconnect()
		end
		spaceConn = nil
		local _result_3 = activatedConn
		if _result_3 ~= nil then
			_result_3:Disconnect()
		end
		activatedConn = nil
		released = true
		if claimButton then
			claimButton.Active = false
		end
	end)
end
-- Called once at startup — all event listeners live here, gated by isGameActive
local function init()
	-- Comptage continu du multiplier : on interpole le nombre affiché de l'ancienne
	-- valeur vers la nouvelle sur la durée d'un tick, donc il passe par tous les
	-- nombres intermédiaires (lent au début, de plus en plus vite).
	RunService.RenderStepped:Connect(function(dt)
		if not isGameActive or not multiplierText then
			return nil
		end
		if multiplierElapsed < MULTIPLIER_TICK_RATE then
			multiplierElapsed = math.min(multiplierElapsed + dt, MULTIPLIER_TICK_RATE)
			local a = multiplierElapsed / MULTIPLIER_TICK_RATE
			displayedMultiplier = multiplierFrom + (multiplierTo - multiplierFrom) * a
		else
			displayedMultiplier = multiplierTo
		end
		multiplierText.Text = `{formatMultiplier(displayedMultiplier)}x`
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
		local _result = spaceConn
		if _result ~= nil then
			_result:Disconnect()
		end
		spaceConn = nil
		local _result_1 = activatedConn
		if _result_1 ~= nil then
			_result_1:Disconnect()
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
	Events.PerfectParryEffectEvent.OnClientEvent:Connect(function()
		-- Le hold s'arrête et l'animation de projection parry se joue.
		ButtonAnimations.playParry()
		-- Son d'explosion joué côté serveur (3D, entendu par tous)
		-- Son d'épée : clone du template — asset déjà en mémoire, aucun délai de buffering
		local parrySound = parrySoundTemplate:Clone()
		parrySound.Parent = SoundService
		parrySound:Play()
		parrySound.Ended:Connect(function()
			return parrySound:Destroy()
		end)
		local character = Players.LocalPlayer.Character
		local _result = character
		if _result ~= nil then
			_result = _result:FindFirstChild("HumanoidRootPart")
		end
		local hrp = _result
		-- Caméra cinématique : au-dessus et derrière le joueur pour voir la projection.
		-- L'orbite est stoppée — le tracking parry ci-dessous prend la main sur la CFrame.
		CameraController.StopOrbit()
		CameraController.SetCinematic()
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = baseFov
		end
		if hrp then
			-- Au moment du parry, le joueur faisait face au bouton → LookVector pointe vers lui
			-- On positionne la caméra dans cette direction pour voir le joueur s'envoler
			local behindDir = hrp.CFrame.LookVector
			local CAM_BEHIND = 12
			local CAM_HEIGHT = 8
			local _result_1 = parryKnockbackCamConn
			if _result_1 ~= nil then
				_result_1:Disconnect()
			end
			parryKnockbackCamConn = RunService.RenderStepped:Connect(function()
				local cam = Workspace.CurrentCamera
				if not cam then
					return nil
				end
				local _position = hrp.Position
				local _arg0 = behindDir * CAM_BEHIND
				local _vector3 = Vector3.new(0, CAM_HEIGHT, 0)
				local camPos = _position + _arg0 + _vector3
				local _position_1 = hrp.Position
				local _vector3_1 = Vector3.new(0, 1, 0)
				cam.CFrame = CFrame.new(camPos, _position_1 + _vector3_1)
			end)
		end
		if not hrp then
			return nil
		end
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.zero
		attachment.Parent = hrp
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.4, Color3.new(1, 0.9, 0.2)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 0.6)) })
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(12, 22)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 0
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Brightness = 4
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Parent = attachment
		-- Burst instantané
		emitter:Emit(50)
		task.delay(1.5, function()
			return attachment:Destroy()
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
		-- Safety net: stop the held pose if the game ended on death (no release/parry
		-- fired). After a normal release or a parry the loop is already stopped, so
		-- this is a no-op and never cuts the release/parry one-shot.
		ButtonAnimations.stop()
		if not exploded then
			local wasParry = parryKnockbackCamConn ~= nil
			local _result = parryKnockbackCamConn
			if _result ~= nil then
				_result:Disconnect()
			end
			parryKnockbackCamConn = nil
			-- Parry : reset instantané (la caméra trackait déjà le joueur, pas besoin de tween)
			-- Release normal : tween fluide depuis la position cinématique de jeu
			if wasParry then
				CameraController.BringBackPlayerCamera(0)
			else
				CameraController.BringBackPlayerCamera()
			end
			-- resetPostProcess() retiré ici : déjà appelé dans endInput() pour la release,
			-- et la FOV est reset instantanément dans PerfectParryEffectEvent pour la parry.
			-- L'appel ici créait un double tween → zoom glitch.
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
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		if not isGameActive then
			return nil
		end
		MusicController:stopButtonMusic()
		-- 0.2s grace period : release normal encore possible
		task.delay(0.2, function()
			if released then
				return nil
			end
			-- Fenêtre de perfect parry : 0.2s supplémentaires avec espace/clic
			startParryWindow()
		end)
	end)
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(inGameUI)
	local popup = inGameUI:WaitForChild("RocketLaunch")
	local claimButtonFrame = popup:WaitForChild("ClaimButtonFrame")
	claimButton = claimButtonFrame:WaitForChild("ClaimButton")
	multiplierText = popup:WaitForChild("MultiplierText")
	-- Save original sizes/colors on first run so we can restore each game
	if not buttonOriginalSize then
		buttonOriginalSize = claimButton.Size
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
	released = false
	MusicController:playButtonMusic()
	ButtonAnimations.playHold()
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
	-- Reset UI
	multiplierText.Text = `{formatMultiplier(STARTING_MULTIPLIER)}x`
	-- Clean up any leftover connections from a previous game
	local _result_1 = spaceConn
	if _result_1 ~= nil then
		_result_1:Disconnect()
	end
	local _result_2 = activatedConn
	if _result_2 ~= nil then
		_result_2:Disconnect()
	end
	local fireRelease = function()
		if not isGameActive or released then
			return nil
		end
		endInput()
		ButtonAnimations.playRelease()
		Events.ReleaseButtonEvent:FireServer()
	end
	activatedConn = claimButton.Activated:Connect(fireRelease)
end
return {
	init = init,
	setup = setup,
}
