-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Popup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "Popup").Popup
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local startButtonGame = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ButtonInGameModule").startButtonGame
local ButtonInGamePopup
do
	local super = Popup
	ButtonInGamePopup = setmetatable({}, {
		__tostring = function()
			return "ButtonInGamePopup"
		end,
		__index = super,
	})
	ButtonInGamePopup.__index = ButtonInGamePopup
	function ButtonInGamePopup.new(...)
		local self = setmetatable({}, ButtonInGamePopup)
		return self:constructor(...) or self
	end
	function ButtonInGamePopup:constructor(...)
		super.constructor(self, ...)
		self.className = "ButtonInGame"
	end
	function ButtonInGamePopup:Show(player)
		super.Show(self, player)
		local session = ButtonSessionService:getSession(player)
		if not session then
			warn(`ButtonInGamePopup: No session found for {player.Name}`)
			return nil
		end
		startButtonGame(player, session)
	end
end
return {
	ButtonInGamePopup = ButtonInGamePopup,
}
