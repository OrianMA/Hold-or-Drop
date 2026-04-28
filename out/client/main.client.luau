-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
Events.ButtonTriggerEvent.OnClientEvent:Connect(function(cameraPosPart)
	CameraController.SetCinematic()
	CameraController.AnimateTo(cameraPosPart.CFrame)
end)
