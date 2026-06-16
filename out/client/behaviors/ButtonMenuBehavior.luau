-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- onGameStart is called with inGameUI once the player clicks StartButton
local function init(onGameStart)
	local startConn
	local quitConn
	-- UI is guaranteed to exist after the server triggered this event
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local inGameUI = playerGui:WaitForChild("InGameUI")
	local buttonMenu = inGameUI:WaitForChild("ButtonMenu")
	local startButton = buttonMenu:WaitForChild("StartButton")
	local quitButton = buttonMenu:WaitForChild("QuitButton")
	local DisconnectEvents
	Events.ButtonTriggerEvent.OnClientEvent:Connect(function(cameraPosPart)
		CameraController.SetCinematic()
		CameraController.AnimateTo(cameraPosPart.CFrame)
		-- Menu is open → hide the persistent HUD behind it.
		InGameUIController:disable()
		DisconnectEvents()
		startConn = startButton.Activated:Connect(function()
			DisconnectEvents()
			Events.StartButtonClickedEvent:FireServer()
			-- Keep the HUD hidden during gameplay — it comes back when the
			-- EndGameButton (ButtonFinishGame) opens.
			onGameStart(inGameUI)
		end)
		quitConn = quitButton.Activated:Connect(function()
			DisconnectEvents()
			Events.QuitButtonClickedEvent:FireServer()
			CameraController.BringBackPlayerCamera()
			-- Cancelled the menu → restore the HUD.
			InGameUIController:enable()
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
