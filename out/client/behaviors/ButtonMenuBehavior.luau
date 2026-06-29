-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local ButtonAnimations = TS.import(script, script.Parent, "ButtonAnimations").ButtonAnimations
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
	Events.ButtonTriggerEvent.OnClientEvent:Connect(function(cameraPosPart, cameraPivotPart)
		-- Dynamic orbit: starts at cameraPosPart, always looks at cameraPivotPart,
		-- player can rotate. Persists into the hold (camera stays on the rocket).
		CameraController.StartOrbit(cameraPosPart.CFrame, cameraPivotPart)
		-- Hand reaches onto the button while the menu is open.
		ButtonAnimations.playInteract()
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
			-- Cancelled the menu → play the "quit" clip, which chains out of the
			-- frozen "hand on button" pose and blends back to the default Roblox
			-- animations at its end. Restore the HUD.
			ButtonAnimations.playQuit()
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
