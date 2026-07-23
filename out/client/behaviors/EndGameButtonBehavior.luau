-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _EndGameAnimation = TS.import(script, script.Parent.Parent, "ui", "EndGameAnimation")
local cancelActiveRun = _EndGameAnimation.cancelActiveRun
local runEndGameAnimation = _EndGameAnimation.runEndGameAnimation
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local FloatingReward = TS.import(script, script.Parent.Parent, "ui", "FloatingReward").FloatingReward
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
local ButtonAnimations = TS.import(script, script.Parent, "ButtonAnimations").ButtonAnimations
-- Entry point for the ButtonFinishGame UI state on the client.
-- Server fires EndGameStartEvent after the popup has been shown — we resolve
-- the frame and hand off to the animation orchestrator. When the animation
-- completes we tell the server to hide the popup (single source of truth).
local function init()
	Events.EndGameStartEvent.OnClientEvent:Connect(function(baseCash, multiplier, lossMultiplier)
		-- The finish popup is opening — bring back the persistent HUD that the
		-- ButtonMenu hid, so the payout animation can fly cash into it.
		InGameUIController:enable()
		-- Payout screen is up → return the rig to the default Roblox animations
		-- (ends a still-playing release clip).
		ButtonAnimations.restoreDefault()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local inGameUI = playerGui:WaitForChild("InGameUI")
		local frame = inGameUI:WaitForChild("ButtonFinishGame")
		task.spawn(function()
			runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, function()
				Events.EndGameFinishedEvent:FireServer()
				-- Run fully over → ease the BGM back in (also covered by respawn on death).
				MusicController.resumeBgm()
			end)
		end)
	end)
	-- Another popup opened while the payout was pending — typically the player
	-- re-triggered the button or the rocket during the release delay, or mid-animation.
	-- The finish screen is dropped entirely (no popup, no HUD restore, no BGM resume):
	-- the screen they just opened keeps the focus, and the gain leaves as one floating
	-- text that fades on the spot. `earned` is the server's total; a running animation
	-- overrides it with what its chunks have not already banked.
	Events.EndGamePayoutFlushEvent.OnClientEvent:Connect(function(earned)
		local remaining = cancelActiveRun()
		-- Nothing was animating and a reward text is already on screen (losing-explosion
		-- consolation still in flight) — that text is the gain, don't stack a second one.
		if remaining == nil and FloatingReward:isActive() then
			return nil
		end
		local _condition = remaining
		if _condition == nil then
			_condition = earned
		end
		local amount = _condition
		if amount <= 0 then
			-- Everything already landed in the HUD — just close the server-side pending.
			Events.EndGameFinishedEvent:FireServer()
			return nil
		end
		FloatingReward:show(amount, "fade")
	end)
end
return {
	init = init,
}
