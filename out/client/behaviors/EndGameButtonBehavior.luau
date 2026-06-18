-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local runEndGameAnimation = TS.import(script, script.Parent.Parent, "ui", "EndGameAnimation").runEndGameAnimation
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
-- Entry point for the ButtonFinishGame UI state on the client.
-- Server fires EndGameStartEvent after the popup has been shown — we resolve
-- the frame and hand off to the animation orchestrator. When the animation
-- completes we tell the server to hide the popup (single source of truth).
local function init()
	Events.EndGameStartEvent.OnClientEvent:Connect(function(baseCash, multiplier, lossMultiplier, multRebirth)
		-- The finish popup is opening — bring back the persistent HUD that the
		-- ButtonMenu hid, so the payout animation can fly cash into it.
		InGameUIController:enable()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local inGameUI = playerGui:WaitForChild("InGameUI")
		local frame = inGameUI:WaitForChild("ButtonFinishGame")
		task.spawn(function()
			runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, multRebirth, function()
				Events.EndGameFinishedEvent:FireServer()
				-- Run fully over → ease the BGM back in (also covered by respawn on death).
				MusicController.resumeBgm()
			end)
		end)
	end)
end
return {
	init = init,
}
