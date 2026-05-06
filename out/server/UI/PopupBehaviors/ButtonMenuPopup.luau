-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
local endButtonGame = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ButtonInGameModule").endButtonGame
local Popup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "Popup").Popup
local ButtonMenuPopup
do
	local super = Popup
	ButtonMenuPopup = setmetatable({}, {
		__tostring = function()
			return "ButtonMenuPopup"
		end,
		__index = super,
	})
	ButtonMenuPopup.__index = ButtonMenuPopup
	function ButtonMenuPopup.new(...)
		local self = setmetatable({}, ButtonMenuPopup)
		return self:constructor(...) or self
	end
	function ButtonMenuPopup:constructor(...)
		super.constructor(self, ...)
		self.className = "ButtonMenu"
	end
	function ButtonMenuPopup:Show(player)
		super.Show(self, player)
		local startConn, quitConn
		startConn = Events.StartButtonClickedEvent.OnServerEvent:Connect(function(p)
			if p ~= player then
				return nil
			end
			startConn:Disconnect()
			quitConn:Disconnect()
			UiService:Show(player, PopupType.ButtonInGame)
		end)
		quitConn = Events.QuitButtonClickedEvent.OnServerEvent:Connect(function(p)
			if p ~= player then
				return nil
			end
			startConn:Disconnect()
			quitConn:Disconnect()
			endButtonGame(player)
		end)
	end
end
return {
	ButtonMenuPopup = ButtonMenuPopup,
}
