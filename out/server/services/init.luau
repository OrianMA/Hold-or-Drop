-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local ButtonTriggerService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonTriggerService").ButtonTriggerService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local CharacterService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "CharacterService").CharacterService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local ShopService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ShopService").ShopService
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
local PopupConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupConfig").PopupConfig
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
local services = { {
	init = function(self)
		UiService:init(PopupConfig)
	end,
}, PlayerDataService, PlayerProgressionService, ShopService, RoomService, ButtonTriggerService, CharacterService, EndGameButtonModule, {
	init = function(self)
		Players.PlayerRemoving:Connect(function(player)
			ButtonSessionService:cleanup(player)
		end)
	end,
} }
return {
	services = services,
}
