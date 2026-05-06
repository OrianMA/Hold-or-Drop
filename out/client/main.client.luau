-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
Events.ButtonTriggerEvent.OnClientEvent:Connect(function(cameraPosPart)
	CameraController.SetCinematic()
	CameraController.AnimateTo(cameraPosPart.CFrame)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local mainUI = playerGui:WaitForChild("MainUI")
	local buttonMenu = mainUI:WaitForChild("ButtonMenu")
	local startButton = buttonMenu:WaitForChild("StartButton")
	startButton.Activated:Connect(function()
		Events.StartButtonClickedEvent:FireServer()
	end)
end)
