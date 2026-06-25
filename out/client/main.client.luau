-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local StarterGui = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").StarterGui
local initButtonMenu = TS.import(script, script.Parent, "behaviors", "ButtonMenuBehavior").init
local _ButtonInGameBehavior = TS.import(script, script.Parent, "behaviors", "ButtonInGameBehavior")
local initButtonInGame = _ButtonInGameBehavior.init
local setupButtonInGame = _ButtonInGameBehavior.setup
local initEndGameButton = TS.import(script, script.Parent, "behaviors", "EndGameButtonBehavior").init
local MoneyDisplay = TS.import(script, script.Parent, "ui", "MoneyDisplay").MoneyDisplay
local initInformationText = TS.import(script, script.Parent, "ui", "InformationText").init
local initRoomPrompts = TS.import(script, script.Parent, "rooms", "RoomPromptController").init
local initOwnerIndicator = TS.import(script, script.Parent, "rooms", "OwnerIndicatorController").init
local initCommunityJoin = TS.import(script, script.Parent, "rooms", "CommunityJoinController").init
local initShopMenu = TS.import(script, script.Parent, "behaviors", "ShopBehavior").init
local initShopItems = TS.import(script, script.Parent, "behaviors", "ShopItemsController").init
local initShopMoneyBuy = TS.import(script, script.Parent, "behaviors", "ShopMoneyBuyBehavior").init
local initBoostShop = TS.import(script, script.Parent, "behaviors", "BoostShopController").init
local initRebirthMenu = TS.import(script, script.Parent, "behaviors", "RebirthMenuBehavior").init
local initRebirthController = TS.import(script, script.Parent, "behaviors", "RebirthMenuController").init
local initHudProgression = TS.import(script, script.Parent, "behaviors", "HudProgressionController").init
local MusicController = TS.import(script, script.Parent, "audio", "MusicController").MusicController
local initAudioVisualizer = TS.import(script, script.Parent, "ui", "AudioVisualizer").init
local initNeonPipePulse = TS.import(script, script.Parent, "ui", "NeonPipePulse").init
-- Keep InGameUI (the persistent HUD + popups) alive across respawns. By default a
-- ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
-- references each behavior caches at startup — leaving ButtonMenu and the rest
-- non-functional after death.
-- The authoritative fix is `InGameUI.ResetOnSpawn = false` set directly on the
-- ScreenGui in Studio (the idiomatic per-GUI Roblox flag). We also set the
-- player-wide flag here as a belt-and-braces guard in case a future ScreenGui
-- is added without thinking about its ResetOnSpawn.
StarterGui.ResetPlayerGuiOnSpawn = false
initButtonInGame()
initEndGameButton()
MoneyDisplay:init()
initInformationText()
initRoomPrompts()
initOwnerIndicator()
initCommunityJoin()
initButtonMenu(setupButtonInGame)
initShopMenu()
initShopItems()
initShopMoneyBuy()
initBoostShop()
initRebirthMenu()
initRebirthController()
initHudProgression()
MusicController:init()
initAudioVisualizer()
initNeonPipePulse()
