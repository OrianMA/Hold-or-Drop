-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
-- Called once at startup — registers all game-state event listeners
local function init()
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		print("Button exploded!")
	end)
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		CameraController.BringBackPlayerCamera()
		print(`Game over — exploded: {exploded} | cash: {cashEarned} | {multiplier}x`)
	end)
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(mainUI)
	local buttonInGame = mainUI:WaitForChild("ButtonInGame")
	local releaseButton = buttonInGame:WaitForChild("ReleaseButton")
	local multiplierLabel = buttonInGame:WaitForChild("MultiplierLabel")
	local progressBar = buttonInGame:WaitForChild("ProgressBar")
	local fill = progressBar:WaitForChild("Fill")
	multiplierLabel.Text = "1x"
	fill.Size = UDim2.new(0, 0, fill.Size.Y.Scale, 0)
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		multiplierLabel.Text = `{multiplier}x`
	end)
	local fillTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	Events.ProgressUpdateEvent.OnClientEvent:Connect(function(progress)
		TweenService:Create(fill, fillTweenInfo, {
			Size = UDim2.new(progress, 0, fill.Size.Y.Scale, 0),
		}):Play()
	end)
	local released = false
	local spaceConn
	local fireRelease = function()
		if released then
			return nil
		end
		released = true
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
end
return {
	init = init,
	setup = setup,
}
