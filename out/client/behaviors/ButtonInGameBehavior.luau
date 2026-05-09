-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
-- Called once at startup — registers all game-state event listeners
local function init()
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		CameraController.BringBackPlayerCamera()
		print(`Game over — exploded: {exploded} | cash: {cashEarned} | {multiplier}x`)
	end)
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(mainUI)
	local popup = mainUI:WaitForChild("ButtonInGame")
	local releaseButton = popup:WaitForChild("ReleaseButton")
	local baseCashText = popup:WaitForChild("BaseCashText")
	local sliderParent = popup:WaitForChild("Slider")
	local multiplierLabel = sliderParent:WaitForChild("MultiplierLabel")
	local progressBarParent = sliderParent:WaitForChild("ProgressBar")
	local progressionIndicator = progressBarParent:WaitForChild("ProgressionIndicator")
	multiplierLabel.Text = "1x"
	progressionIndicator.Position = UDim2.new(0, 0, 0.5, 0)
	Events.BaseCashEvent.OnClientEvent:Connect(function(baseCash)
		baseCashText.Text = `${baseCash}`
	end)
	local BASE_MULTIPLIER_TEXT_SIZE = multiplierLabel.TextSize
	local SIZE_GROWTH_PER_UPDATE = 3
	local elasticTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	local multiplierTextSize = BASE_MULTIPLIER_TEXT_SIZE
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		multiplierLabel.Text = `{multiplier}x`
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE
		TweenService:Create(multiplierLabel, elasticTweenInfo, {
			TextSize = multiplierTextSize,
		}):Play()
	end)
	local fillTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	Events.ProgressUpdateEvent.OnClientEvent:Connect(function(progress)
		TweenService:Create(progressionIndicator, fillTweenInfo, {
			Position = UDim2.new(progress, 0, 0.5, 0),
		}):Play()
	end)
	local released = false
	local spaceConn
	local fireRelease = function()
		if released then
			return nil
		end
		released = true
		releaseButton.Active = false
		spaceConn:Disconnect()
		Events.ReleaseButtonEvent:FireServer()
	end
	releaseButton.Activated:Connect(fireRelease)
	spaceConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return nil
		end
		if input.KeyCode == Enum.KeyCode.Space then
			fireRelease()
		end
	end)
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		print("Button exploded!")
		-- Disable input after the 0.2s grace period if the player hasn't already released
		task.delay(0.2, function()
			if not released then
				releaseButton.Active = false
				spaceConn:Disconnect()
			end
		end)
	end)
end
return {
	init = init,
	setup = setup,
}
