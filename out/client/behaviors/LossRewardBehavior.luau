-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local FloatingReward = TS.import(script, script.Parent.Parent, "ui", "FloatingReward").FloatingReward
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
-- ── Losing-explosion consolation ────────────────────────────────────────────────
--
-- On a losing explosion there is NO ButtonFinishGame popup (see §6.3). Instead the
-- player gets a flat consolation (baseCash / 3, computed server-side) shown as a
-- single "+amount" text that jumps then flies into the money HUD (FloatingReward,
-- "fly" ending). The text banks the cash on arrival and fires EndGameFinishedEvent
-- so the server credits the real Money via the shared pendingEarned path.
local function init()
	Events.LossRewardEvent.OnClientEvent:Connect(function(amount)
		-- The HUD was hidden during gameplay; bring it back so the money counter is
		-- visible for the text to fly into (GameResultEvent already stopped the held
		-- pose and returned the camera).
		InGameUIController:enable()
		-- Run fully over → ease the BGM back in once the text has landed.
		FloatingReward:show(amount, "fly", function()
			return MusicController.resumeBgm()
		end)
	end)
end
return {
	init = init,
}
