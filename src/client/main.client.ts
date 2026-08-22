import { StarterGui } from "@rbxts/services";
import { init as initButtonMenu } from "./behaviors/ButtonMenuBehavior";
import { init as initRocketLaunch, setup as setupRocketLaunch } from "./behaviors/RocketLaunchBehavior";
import { init as initEndGameButton } from "./behaviors/EndGameButtonBehavior";
import { init as initLossReward } from "./behaviors/LossRewardBehavior";
import { MoneyDisplay } from "./ui/MoneyDisplay";
import { FloatingCash } from "./ui/FloatingCash";
import { init as initInformationText } from "./ui/InformationText";
import { init as initInformationTextTest } from "./ui/InformationTextTest";
import { init as initRoomPrompts } from "./rooms/RoomPromptController";
import { init as initOwnerIndicator } from "./rooms/OwnerIndicatorController";
import { init as initCommunityJoin } from "./rooms/CommunityJoinController";
import { init as initCommunityMascot } from "./rooms/CommunityMascotController";
import { init as initShopMenu } from "./behaviors/ShopBehavior";
import { init as initShopItems } from "./behaviors/ShopItemsController";
import { init as initShopMoneyBuy } from "./behaviors/ShopMoneyBuyBehavior";
import { init as initBoostShop } from "./behaviors/BoostShopController";
import { init as initMultiplierPass } from "./behaviors/MultiplierPassController";
import { init as initMoneyBoost } from "./behaviors/MoneyBoostController";
import { init as initRebirthMenu } from "./behaviors/RebirthMenuBehavior";
import { init as initRebirthController } from "./behaviors/RebirthMenuController";
import { init as initDailyRewards } from "./behaviors/DailyRewardsBehavior";
import { init as initQuests } from "./behaviors/QuestsBehavior";
import { init as initScrollShop } from "./behaviors/ScrollShopController";
import { ScrollTokenDisplay } from "./ui/ScrollTokenDisplay";
import { init as initHudProgression } from "./behaviors/HudProgressionController";
import { init as initCostTextRotator } from "./ui/CostTextRotator";
import { MusicController } from "./audio/MusicController";
import { init as initUiClickSound } from "./audio/UiClickSound";
import { init as initAudioVisualizer } from "./ui/AudioVisualizer";
import { init as initNeonPipePulse } from "./ui/NeonPipePulse";
import { init as initMegaRocketVisuals } from "./ui/MegaRocketVisuals";
import { init as initMegaRocketCheat } from "./MegaRocketCheat";
import { init as initDailyRewardCheat } from "./DailyRewardCheat";
import { init as initQuestCheat } from "./QuestCheat";
import { init as initTutorial } from "./tutorial/TutorialController";

// Keep InGameUI (the persistent HUD + popups) alive across respawns. By default a
// ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
// references each behavior caches at startup — leaving ButtonMenu and the rest
// non-functional after death.
// The authoritative fix is `InGameUI.ResetOnSpawn = false` set directly on the
// ScreenGui in Studio (the idiomatic per-GUI Roblox flag). We also set the
// player-wide flag here as a belt-and-braces guard in case a future ScreenGui
// is added without thinking about its ResetOnSpawn.
StarterGui.ResetPlayerGuiOnSpawn = false;

initRocketLaunch();
initEndGameButton();
initLossReward();
MoneyDisplay.init();
FloatingCash.init();
initInformationText();
initInformationTextTest();
initRoomPrompts();
initOwnerIndicator();
initCommunityJoin();
initCommunityMascot();
initButtonMenu(setupRocketLaunch);
initShopMenu();
initShopItems();
initShopMoneyBuy();
initBoostShop();
initMultiplierPass();
initMoneyBoost();
initRebirthMenu();
initRebirthController();
initDailyRewards();
ScrollTokenDisplay.init();
initQuests();
initScrollShop();
initHudProgression();
initCostTextRotator();
MusicController.init();
initUiClickSound();
initAudioVisualizer();
initNeonPipePulse();
initMegaRocketVisuals();
initMegaRocketCheat();
initDailyRewardCheat();
initQuestCheat();
initTutorial();
