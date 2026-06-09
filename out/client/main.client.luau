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
local initShopMenu = TS.import(script, script.Parent, "behaviors", "ShopBehavior").init
-- Keep MainUI (the persistent HUD + popups) alive across respawns. By default a
-- ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
-- references each behavior caches at startup — leaving ButtonMenu and the rest
-- non-functional after death.
-- The authoritative fix is `MainUI.ResetOnSpawn = false` set directly on the
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
initButtonMenu(setupButtonInGame)
initShopMenu()
