-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Popup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "Popup").Popup
-- The popup itself is a thin Show/Hide wrapper around the ButtonFinishGame frame.
-- All animation logic lives client-side (EndGameButtonBehavior) and is triggered
-- by the server through Events.EndGameStartEvent after Show().
local ButtonFinishGamePopup
do
	local super = Popup
	ButtonFinishGamePopup = setmetatable({}, {
		__tostring = function()
			return "ButtonFinishGamePopup"
		end,
		__index = super,
	})
	ButtonFinishGamePopup.__index = ButtonFinishGamePopup
	function ButtonFinishGamePopup.new(...)
		local self = setmetatable({}, ButtonFinishGamePopup)
		return self:constructor(...) or self
	end
	function ButtonFinishGamePopup:constructor(...)
		super.constructor(self, ...)
		self.className = "ButtonFinishGame"
	end
end
return {
	ButtonFinishGamePopup = ButtonFinishGamePopup,
}
