-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Popup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "Popup").Popup
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local startButtonGame = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ButtonInGameModule").startButtonGame
local RocketLaunchPopup
do
	local super = Popup
	RocketLaunchPopup = setmetatable({}, {
		__tostring = function()
			return "RocketLaunchPopup"
		end,
		__index = super,
	})
	RocketLaunchPopup.__index = RocketLaunchPopup
	function RocketLaunchPopup.new(...)
		local self = setmetatable({}, RocketLaunchPopup)
		return self:constructor(...) or self
	end
	function RocketLaunchPopup:constructor(...)
		super.constructor(self, ...)
		self.className = "RocketLaunch"
	end
	function RocketLaunchPopup:Show(player)
		super.Show(self, player)
		local session = ButtonSessionService:getSession(player)
		if not session then
			warn(`RocketLaunchPopup: No session found for {player.Name}`)
			return nil
		end
		startButtonGame(player, session)
	end
end
return {
	RocketLaunchPopup = RocketLaunchPopup,
}
