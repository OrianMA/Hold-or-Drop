-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local MainUIController = TS.import(script, script.Parent.Parent, "ui", "MainUIController").MainUIController
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- onGameStart is called with mainUI once the player clicks StartButton
local function init(onGameStart)
	local startConn
	local quitConn
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local DisconnectEvents
	Events.ButtonTriggerEvent.OnClientEvent:Connect(function(cameraPosPart)
		print("game supposed to start")
		-- Hide the persistent HUD while the player is on the button — re-enabled
		-- on Quit (below) or on GameResultEvent (ButtonInGameBehavior).
		MainUIController:disable()
		-- Re-fetch UI elements each time — references become stale after respawn if ResetOnSpawn=true
		local mainUI = playerGui:WaitForChild("MainUI")
		local buttonMenu = mainUI:WaitForChild("ButtonMenu")
		local startButton = buttonMenu:WaitForChild("StartButton")
		local quitButton = buttonMenu:WaitForChild("QuitButton")
		CameraController.SetCinematic()
		CameraController.AnimateTo(cameraPosPart.CFrame)
		DisconnectEvents()
		startConn = startButton.Activated:Connect(function()
			DisconnectEvents()
			Events.StartButtonClickedEvent:FireServer()
			onGameStart(mainUI)
			print("game supposed to start")
		end)
		quitConn = quitButton.Activated:Connect(function()
			DisconnectEvents()
			Events.QuitButtonClickedEvent:FireServer()
			CameraController.BringBackPlayerCamera()
			MainUIController:enable()
		end)
	end)
	function DisconnectEvents()
		local _result = startConn
		if _result ~= nil then
			_result:Disconnect()
		end
		local _result_1 = quitConn
		if _result_1 ~= nil then
			_result_1:Disconnect()
		end
	end
end
return {
	init = init,
}
