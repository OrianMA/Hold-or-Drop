-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local ButtonTriggerService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonTriggerService").ButtonTriggerService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local CharacterService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "CharacterService").CharacterService
local PopupConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupConfig").PopupConfig
local services = { {
	init = function(self)
		UiService:init(PopupConfig)
	end,
}, ButtonTriggerService, CharacterService, {
	init = function(self)
		Players.PlayerRemoving:Connect(function(player)
			ButtonSessionService:cleanup(player)
		end)
	end,
} }
return {
	services = services,
}
