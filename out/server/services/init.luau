-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local ButtonTriggerService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonTriggerService").ButtonTriggerService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local CharacterService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "CharacterService").CharacterService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local MoneyProductService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "MoneyProductService").MoneyProductService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local BoostService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "BoostService").BoostService
local ShopService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ShopService").ShopService
local RebirthService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "RebirthService").RebirthService
local DailyRewardService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "DailyRewardService").DailyRewardService
local QuestService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "QuestService").QuestService
local ScrollShopService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ScrollShopService").ScrollShopService
local LeaderboardService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "LeaderboardService").LeaderboardService
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
local TutorialService = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialService").TutorialService
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
local PopupConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupConfig").PopupConfig
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
local MegaRocketService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "MegaRocketService").MegaRocketService
local services = { {
	init = function(self)
		UiService:init(PopupConfig)
	end,
}, PlayerDataService, MoneyProductService, PlayerProgressionService, BoostService, ShopService, RebirthService, DailyRewardService, QuestService, LeaderboardService, AnalyticsService, TutorialService, RoomService, ButtonTriggerService, CharacterService, EndGameButtonModule, MegaRocketService, ScrollShopService, {
	init = function(self)
		Players.PlayerRemoving:Connect(function(player)
			ButtonSessionService:cleanup(player)
		end)
	end,
} }
return {
	services = services,
}
