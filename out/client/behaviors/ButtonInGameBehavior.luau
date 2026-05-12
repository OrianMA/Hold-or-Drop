-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Lighting = _services.Lighting
local RunService = _services.RunService
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
local Workspace = _services.Workspace
-- UI refs — assigned on first setup(), never change after
local releaseButton
local baseCashText
local multiplierLabel
local progressionIndicator
local vignetteCanvas
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
local baseMultiplierTextSize = 0
local shakeAmplitude = 0
local spaceConn
local activatedConn
local SIZE_GROWTH_PER_UPDATE = 4
local MAX_MULTIPLIER_SIZE_INCREASE = 80
local MAX_SHAKE_AMPLITUDE = 0.08
local MAX_BLOOM_INTENSITY = 1.5
local MIN_VIGNETTE_TRANSPARENCY = 0.2
local UpgradeMultiplayerTI = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ReleaseButtonDesapearTI = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FillProgressBarTI = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local PostProcessTI = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ResetPostProcessTI = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "VignetteCanvas"
	canvas.Size = UDim2.new(1, 0, 1, 0)
	canvas.Position = UDim2.new(0, 0, 0, 0)
	canvas.BackgroundTransparency = 1
	canvas.GroupTransparency = 1
	canvas.ZIndex = 10
	canvas.Parent = mainUI
	-- Four gradient edges: top, bottom, left, right
	-- Rotation controls which side is opaque (0 = opaque at start of gradient direction)
	createVignetteEdge(canvas, 90, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.new(1, 0, 0.45, 0))
	createVignetteEdge(canvas, 270, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0), UDim2.new(1, 0, 0.45, 0))
	createVignetteEdge(canvas, 0, Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0), UDim2.new(0.45, 0, 1, 0))
	createVignetteEdge(canvas, 180, Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.new(0.45, 0, 1, 0))
	return canvas
end
local function resetPostProcess(instant)
	if instant == nil then
		instant = false
	end
	local ti = if instant then TweenInfo.new(0) else ResetPostProcessTI
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
-- Called once at startup — all event listeners live here, gated by isGameActive
local function init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "HoldOrDropCC"
	colorCorrection.Parent = Lighting
	bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Name = "HoldOrDropBloom"
	bloomEffect.Intensity = 0
	bloomEffect.Size = 24
	bloomEffect.Threshold = 0.95
	bloomEffect.Parent = Lighting
	-- Shake loop — runs after the camera updates each frame, amplitude controlled per-game
	RunService:BindToRenderStep("HoldOrDropShake", Enum.RenderPriority.Camera.Value + 1, function()
		if shakeAmplitude <= 0 then
			return nil
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return nil
		end
		local offset = CFrame.Angles((math.random() - 0.5) * shakeAmplitude, (math.random() - 0.5) * shakeAmplitude, (math.random() - 0.5) * shakeAmplitude * 0.3)
		camera.CFrame = camera.CFrame * offset
	end)
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		CameraController.BringBackPlayerCamera()
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
		multiplierLabel.Text = `{multiplier}x`
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE
		local _exp = multiplierTextSize
		local _condition = multiplierTextOriginalSize
		if _condition == nil then
			_condition = 0
		end
		local factor = math.clamp((_exp - _condition) / MAX_MULTIPLIER_SIZE_INCREASE, 0, 1)
		local targetTextColor = (multiplierTextOriginalColor or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 0, 0), factor)
		TweenService:Create(multiplierLabel, UpgradeMultiplayerTI, {
			TextSize = multiplierTextSize,
			TextColor3 = targetTextColor,
		}):Play()
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
		print("Button exploded!")
		-- Grace period: player can still release to cancel the explosion
		task.delay(0.2, function()
			if not released then
				endInput()
			end
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
	isGameActive = true
	released = false
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
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	local _result_1 = activatedConn
	if _result_1 ~= nil then
		_result_1:Disconnect()
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
