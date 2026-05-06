-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local UserInputService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").UserInputService
-- Called once at startup — registers all game-state event listeners
local function init()
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		-- TODO: update multiplier label in ButtonInGame UI
		print(`Multiplier: {multiplier}x`)
	end)
	Events.RiskUpdateEvent.OnClientEvent:Connect(function(risk)
		-- TODO: update risk indicator in ButtonInGame UI (risk is 0–1)
		print(`Risk: {math.round(risk * 100)}%`)
	end)
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		-- TODO: screenshake, stress effect, explosion sound/particles
		print("Button exploded!")
	end)
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		CameraController.BringBackPlayerCamera()
		-- TODO: show result popup (cash earned, whether it exploded)
		print(`Game over — exploded: {exploded} | cash: {cashEarned} | {multiplier}x`)
	end)
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(mainUI)
	local buttonInGame = mainUI:WaitForChild("ButtonInGame")
	local releaseButton = buttonInGame:WaitForChild("ReleaseButton")
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
