-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
-- Gives the "moving cost" label on the HUD multiplier buy button a constant, gentle
-- wobble — rotating smoothly between +ANGLE and -ANGLE degrees forever to draw the
-- eye. Purely cosmetic, client-only.
--
-- One looping tween (RepeatCount -1, Reverses true) on the label's Rotation does the
-- whole thing: starting at +ANGLE and easing to -ANGLE with a Sine in/out curve, the
-- reverse brings it back, so it oscillates seamlessly without any per-frame work.
local ANGLE = 10
local TWEEN_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local function init()
	local player = Players.LocalPlayer
	local label = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD"):WaitForChild("BottomList"):WaitForChild("MultiplierBuyButton"):WaitForChild("CostMovingtext")
	label.Rotation = ANGLE
	TweenService:Create(label, TWEEN_INFO, {
		Rotation = -ANGLE,
	}):Play()
end
return {
	init = init,
}
