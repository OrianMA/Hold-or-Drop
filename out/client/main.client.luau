-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local StarterGui = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").StarterGui
local initButtonMenu = TS.import(script, script.Parent, "behaviors", "ButtonMenuBehavior").init
local _RocketLaunchBehavior = TS.import(script, script.Parent, "behaviors", "RocketLaunchBehavior")
local initRocketLaunch = _RocketLaunchBehavior.init
local setupRocketLaunch = _RocketLaunchBehavior.setup
local initEndGameButton = TS.import(script, script.Parent, "behaviors", "EndGameButtonBehavior").init
local initLossReward = TS.import(script, script.Parent, "behaviors", "LossRewardBehavior").init
local MoneyDisplay = TS.import(script, script.Parent, "ui", "MoneyDisplay").MoneyDisplay
local FloatingCash = TS.import(script, script.Parent, "ui", "FloatingCash").FloatingCash
local initInformationText = TS.import(script, script.Parent, "ui", "InformationText").init
local initInformationTextTest = TS.import(script, script.Parent, "ui", "InformationTextTest").init
local initRoomPrompts = TS.import(script, script.Parent, "rooms", "RoomPromptController").init
local initOwnerIndicator = TS.import(script, script.Parent, "rooms", "OwnerIndicatorController").init
local initCommunityJoin = TS.import(script, script.Parent, "rooms", "CommunityJoinController").init
local initCommunityMascot = TS.import(script, script.Parent, "rooms", "CommunityMascotController").init
local initShopMenu = TS.import(script, script.Parent, "behaviors", "ShopBehavior").init
local initShopItems = TS.import(script, script.Parent, "behaviors", "ShopItemsController").init
local initShopMoneyBuy = TS.import(script, script.Parent, "behaviors", "ShopMoneyBuyBehavior").init
local initBoostShop = TS.import(script, script.Parent, "behaviors", "BoostShopController").init
local initMultiplierPass = TS.import(script, script.Parent, "behaviors", "MultiplierPassController").init
local initMoneyBoost = TS.import(script, script.Parent, "behaviors", "MoneyBoostController").init
local initRebirthMenu = TS.import(script, script.Parent, "behaviors", "RebirthMenuBehavior").init
local initRebirthController = TS.import(script, script.Parent, "behaviors", "RebirthMenuController").init
local initDailyRewards = TS.import(script, script.Parent, "behaviors", "DailyRewardsBehavior").init
local initHudProgression = TS.import(script, script.Parent, "behaviors", "HudProgressionController").init
local initCostTextRotator = TS.import(script, script.Parent, "ui", "CostTextRotator").init
local MusicController = TS.import(script, script.Parent, "audio", "MusicController").MusicController
local initUiClickSound = TS.import(script, script.Parent, "audio", "UiClickSound").init
local initAudioVisualizer = TS.import(script, script.Parent, "ui", "AudioVisualizer").init
local initNeonPipePulse = TS.import(script, script.Parent, "ui", "NeonPipePulse").init
local initMegaRocketVisuals = TS.import(script, script.Parent, "ui", "MegaRocketVisuals").init
local initMegaRocketCheat = TS.import(script, script.Parent, "MegaRocketCheat").init
local initDailyRewardCheat = TS.import(script, script.Parent, "DailyRewardCheat").init
local initTutorial = TS.import(script, script.Parent, "tutorial", "TutorialController").init
-- Keep InGameUI (the persistent HUD + popups) alive across respawns. By default a
-- ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
-- references each behavior caches at startup — leaving ButtonMenu and the rest
-- non-functional after death.
-- The authoritative fix is `InGameUI.ResetOnSpawn = false` set directly on the
-- ScreenGui in Studio (the idiomatic per-GUI Roblox flag). We also set the
-- player-wide flag here as a belt-and-braces guard in case a future ScreenGui
-- is added without thinking about its ResetOnSpawn.
StarterGui.ResetPlayerGuiOnSpawn = false
initRocketLaunch()
initEndGameButton()
initLossReward()
MoneyDisplay:init()
FloatingCash:init()
initInformationText()
initInformationTextTest()
initRoomPrompts()
initOwnerIndicator()
initCommunityJoin()
initCommunityMascot()
initButtonMenu(setupRocketLaunch)
initShopMenu()
initShopItems()
initShopMoneyBuy()
initBoostShop()
initMultiplierPass()
initMoneyBoost()
initRebirthMenu()
initRebirthController()
initDailyRewards()
initHudProgression()
initCostTextRotator()
MusicController:init()
initUiClickSound()
initAudioVisualizer()
initNeonPipePulse()
initMegaRocketVisuals()
initMegaRocketCheat()
initDailyRewardCheat()
initTutorial()
