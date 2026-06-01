-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local ButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ButtonModule").ButtonModule
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
-- Binds the button gameplay to each room. Must init after RoomService (the
-- rooms must exist before we attach a ButtonModule to each one).
local ButtonTriggerService = {
	init = function(self)
		for _, room in RoomService:getRooms() do
			ButtonModule.new(room):bind()
		end
	end,
}
return {
	ButtonTriggerService = ButtonTriggerService,
}
