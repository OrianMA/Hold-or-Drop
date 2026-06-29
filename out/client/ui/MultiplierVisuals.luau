-- Compiled with roblox-ts v3.0.0
-- Shared snapshot of the in-game multiplier label's last "peak" appearance.
-- Captured by RocketLaunchBehavior on every MultiplierUpdate, consumed by
-- EndGameAnimation so the ButtonFinishGame popup opens with a MultiplierText
-- matching the size + color the player was looking at when the game ended.
local last
local MultiplierVisuals = {
	capture = function(self, size, color)
		last = {
			size = size,
			color = color,
		}
	end,
	getLast = function(self)
		return last
	end,
	clear = function(self)
		last = nil
	end,
}
return {
	MultiplierVisuals = MultiplierVisuals,
}
