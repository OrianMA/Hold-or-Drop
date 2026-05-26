-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local spawnFloatingMultiplierLabel = TS.import(script, script.Parent.Parent, "ui", "FloatingMultiplierLabel").spawnFloatingMultiplierLabel
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local GuiService = _services.GuiService
local Lighting = _services.Lighting
local Players = _services.Players
local ReplicatedStorage = _services.ReplicatedStorage
local RunService = _services.RunService
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
local Workspace = _services.Workspace
-- UI refs — assigned on first setup(), never change after
local releaseButton
local baseCashText
local multiplierLabel
local progressionIndicator
local vignetteCanvas
local floatingTemplate
local buttonOriginalSize
local multiplierTextOriginalSize
local multiplierTextOriginalColor
-- Lighting effects — created once in init()
local colorCorrection
local bloomEffect
-- Per-game state
local isGameActive = false
local released = false
local multiplierTextSize = 0
local previousMultiplier = 1
local shakeAmplitude = 0
local shakeUndoCFrame
local baseFov = 70
local spaceConn
local activatedConn
local parryKnockbackCamConn
local parryAnimTrack
-- Son bouton — joué via playSound() (non-3D, personnel)
local SOUND_BUTTON_EXPLODE_ID = "rbxassetid://133384716023284"
local SOUND_PARRY_ID = "rbxassetid://119580857539801"
-- Template persistant en SoundService : le client garde l'asset en mémoire dès le démarrage.
-- Cloner ce template au moment du parry élimine le fetch CDN et le délai de buffering.
local parrySoundTemplate = (function()
	local sound = Instance.new("Sound")
	sound.Name = "ParrySoundTemplate"
	sound.SoundId = SOUND_PARRY_ID
	sound.Volume = 1
	sound.Parent = SoundService
	return sound
end)()
-- Animation perfect parry — remplace l'ID par celui récupéré depuis la toolbox
local ANIM_PARRY_ID = "rbxassetid://6481315203"
local function playSound(id, volume, pitch)
	if volume == nil then
		volume = 1
	end
	if pitch == nil then
		pitch = 1
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
end
local SIZE_GROWTH_PER_UPDATE = 4
local MAX_MULTIPLIER_SIZE_INCREASE = 80
local MAX_SHAKE_AMPLITUDE = 0.08
local MAX_BLOOM_INTENSITY = 1.5
local MIN_VIGNETTE_TRANSPARENCY = 0.2
local MIN_FOV = 58
local UpgradeMultiplayerTI = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ReleaseButtonDesapearTI = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FillProgressBarTI = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local PostProcessTI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ResetPostProcessTI = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ZoomResetTI = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ExplodeFovPunchTI = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXPLODE_FOV_OVERSHOOT = 18
local PerfectParrytime = 1.6
local function createVignetteEdge(parent, rotation, anchorPoint, position, size)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.AnchorPoint = anchorPoint
	frame.Position = position
	frame.Size = size
	frame.ZIndex = 10
	frame.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	gradient.Rotation = rotation
	gradient.Parent = frame
	return frame
end
local function buildVignette(mainUI)
	local topLeft = GuiService:GetGuiInset()
	local insetY = topLeft.Y
	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "VignetteCanvas"
	canvas.Size = UDim2.new(1, 0, 1, insetY)
	canvas.Position = UDim2.new(0, 0, 0, -insetY)
	canvas.BackgroundTransparency = 1
	canvas.GroupTransparency = 1
	canvas.ZIndex = 1
	canvas.Parent = mainUI
	-- Four gradient edges: top, bottom, left, right
	-- Rotation controls which side is opaque (0 = opaque at start of gradient direction)
	createVignetteEdge(canvas, 90, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.new(1, 0, 0.45, 0))
	createVignetteEdge(canvas, 270, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0), UDim2.new(1, 0, 0.45, 0))
	createVignetteEdge(canvas, 0, Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0), UDim2.new(0.45, 0, 1, 0))
	createVignetteEdge(canvas, 180, Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.new(0.45, 0, 1, 0))
	return canvas
end
local function resetPostProcess(instant, explode)
	if instant == nil then
		instant = false
	end
	if explode == nil then
		explode = false
	end
	local ti = if instant or explode then TweenInfo.new(0) else ResetPostProcessTI
	if vignetteCanvas then
		TweenService:Create(vignetteCanvas, ti, {
			GroupTransparency = 1,
		}):Play()
	end
	if colorCorrection then
		TweenService:Create(colorCorrection, ti, {
			TintColor = Color3.new(1, 1, 1),
			Saturation = 0,
		}):Play()
	end
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
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	spaceConn = nil
	resetPostProcess()
	if releaseButton then
		releaseButton.Active = false
		local tween = TweenService:Create(releaseButton, ReleaseButtonDesapearTI, {
			Size = UDim2.new(0, 0, 0, 0),
		})
		tween:Play()
		tween.Completed:Wait()
		releaseButton.Visible = false
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
	if not releaseButton then
		released = true
		return nil
	end
	-- Le bouton disparaît pendant la fenêtre de parry
	releaseButton.Active = true
	local tween = TweenService:Create(releaseButton, ReleaseButtonDesapearTI, {
		Size = UDim2.new(0, 0, 0, 0),
	})
	tween:Play()
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
	activatedConn = releaseButton.Activated:Connect(fireParry)
	-- Fin de la fenêtre de parry
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
		releaseButton.Active = false
		releaseButton.Visible = false
	end)
end
-- Called once at startup — all event listeners live here, gated by isGameActive
local function init()
	-- Préchargement du son bouton (non-template : joué via playSound à la demande)
	task.spawn(function()
		local s = Instance.new("Sound")
		s.SoundId = SOUND_BUTTON_EXPLODE_ID
		s.Parent = SoundService
		ContentProvider:PreloadAsync({ s })
		s:Destroy()
	end)
	-- Template du label flottant — stocké dans ReplicatedStorage, accessible par tous les clients
	floatingTemplate = ReplicatedStorage:WaitForChild("FloatingMultiplierTemplate")
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "HoldOrDropCC"
	colorCorrection.Parent = Lighting
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
		-- Son joué côté serveur (3D, entendu par tous)
		CameraController.BringBackPlayerCamera(0)
	end)
	Events.PerfectParryEffectEvent.OnClientEvent:Connect(function()
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
		-- Caméra cinématique : au-dessus et derrière le joueur pour voir la projection
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
		-- Animation de projection
		local _humanoid = character
		if _humanoid ~= nil then
			_humanoid = _humanoid:FindFirstChildOfClass("Humanoid")
		end
		local humanoid = _humanoid
		local _animator = humanoid
		if _animator ~= nil then
			_animator = _animator:FindFirstChildOfClass("Animator")
		end
		local animator = _animator
		if animator then
			--[[
				 			const anim = new Instance("Animation");
							anim.AnimationId = ANIM_PARRY_ID;
							parryAnimTrack?.Stop();
							parryAnimTrack = animator.LoadAnimation(anim);
							parryAnimTrack.Priority = Enum.AnimationPriority.Action4;
							parryAnimTrack.Play(); 
			]]
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = baseFov
		end
	end)
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
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
				local _result_1 = parryAnimTrack
				if _result_1 ~= nil then
					_result_1:Stop()
				end
				parryAnimTrack = nil
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
	Events.BaseCashEvent.OnClientEvent:Connect(function(baseCash)
		if not isGameActive or not baseCashText then
			return nil
		end
		baseCashText.Text = `${baseCash}`
	end)
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		if not isGameActive or not multiplierLabel then
			return nil
		end
		local delta = multiplier - previousMultiplier
		previousMultiplier = multiplier
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE
		local _exp = multiplierTextSize
		local _condition = multiplierTextOriginalSize
		if _condition == nil then
			_condition = 0
		end
		local factor = math.clamp((_exp - _condition) / MAX_MULTIPLIER_SIZE_INCREASE, 0, 1)
		-- Capture pour la closure : plusieurs labels peuvent voler en même temps
		local capturedLabel = multiplierLabel
		local capturedMultiplier = multiplier
		local capturedSize = multiplierTextSize
		local capturedColor = (multiplierTextOriginalColor or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 0, 0), factor)
		-- Texte + bump déclenchés à l'impact du label flottant
		local onLabelArrived = function()
			capturedLabel.Text = `{capturedMultiplier}x`
			TweenService:Create(capturedLabel, UpgradeMultiplayerTI, {
				TextSize = capturedSize,
				TextColor3 = capturedColor,
			}):Play()
		end
		if delta > 0 then
			local screenGui = multiplierLabel:FindFirstAncestorOfClass("ScreenGui")
			if screenGui and floatingTemplate then
				spawnFloatingMultiplierLabel(screenGui, floatingTemplate, delta, multiplierLabel, onLabelArrived)
			else
				onLabelArrived()
			end
		end
		-- Effets ambiants immédiats (game-feel, indépendants du label flottant)
		if vignetteCanvas then
			TweenService:Create(vignetteCanvas, PostProcessTI, {
				GroupTransparency = 1 - factor * (1 - MIN_VIGNETTE_TRANSPARENCY),
			}):Play()
		end
		if colorCorrection then
			TweenService:Create(colorCorrection, PostProcessTI, {
				TintColor = Color3.new(1, 1 - factor * 0.5, 1 - factor * 0.5),
				Saturation = -factor * 0.4,
			}):Play()
		end
		if bloomEffect then
			TweenService:Create(bloomEffect, PostProcessTI, {
				Intensity = factor * MAX_BLOOM_INTENSITY,
			}):Play()
		end
		shakeAmplitude = factor * MAX_SHAKE_AMPLITUDE
		local camera = Workspace.CurrentCamera
		if camera then
			TweenService:Create(camera, PostProcessTI, {
				FieldOfView = baseFov - factor * (baseFov - MIN_FOV),
			}):Play()
		end
	end)
	Events.ProgressUpdateEvent.OnClientEvent:Connect(function(progress)
		if not isGameActive or not progressionIndicator then
			return nil
		end
		TweenService:Create(progressionIndicator, FillProgressBarTI, {
			Position = UDim2.new(progress, 0, 0.5, 0),
		}):Play()
	end)
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		if not isGameActive then
			return nil
		end
		playSound(SOUND_BUTTON_EXPLODE_ID, 1)
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
local function setup(mainUI)
	local popup = mainUI:WaitForChild("ButtonInGame")
	releaseButton = popup:WaitForChild("ReleaseButton")
	baseCashText = popup:WaitForChild("BaseCashText")
	local sliderParent = popup:WaitForChild("Slider")
	multiplierLabel = sliderParent:WaitForChild("MultiplierLabel")
	local progressBarParent = sliderParent:WaitForChild("ProgressBar")
	progressionIndicator = progressBarParent:WaitForChild("ProgressionIndicator")
	-- Save original sizes/colors on first run so we can restore each game
	if not buttonOriginalSize then
		buttonOriginalSize = releaseButton.Size
	end
	if not (multiplierTextOriginalSize ~= 0 and multiplierTextOriginalSize == multiplierTextOriginalSize and multiplierTextOriginalSize) then
		multiplierTextOriginalSize = multiplierLabel.TextSize
	end
	if not multiplierTextOriginalColor then
		multiplierTextOriginalColor = multiplierLabel.TextColor3
	end
	if not vignetteCanvas then
		vignetteCanvas = buildVignette(mainUI)
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
	previousMultiplier = 1
	multiplierLabel.TextSize = multiplierTextOriginalSize
	multiplierLabel.TextColor3 = multiplierTextOriginalColor
	multiplierTextSize = multiplierTextOriginalSize
	resetPostProcess(true)
	-- Restore button to full size and re-enable it
	releaseButton.Size = buttonOriginalSize
	releaseButton.Active = true
	releaseButton.Visible = true
	print(releaseButton.Activated)
	-- Reset UI
	multiplierLabel.Text = "1x"
	progressionIndicator.Position = UDim2.new(0, 0, 0.5, 0)
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
		Events.ReleaseButtonEvent:FireServer()
	end
	activatedConn = releaseButton.Activated:Connect(fireRelease)
	spaceConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isGameActive or released then
			return nil
		end
		if input.KeyCode == Enum.KeyCode.Space then
			fireRelease()
		end
	end)
end
return {
	init = init,
	setup = setup,
}
