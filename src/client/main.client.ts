import { StarterGui } from "@rbxts/services";
import { init as initButtonMenu } from "./behaviors/ButtonMenuBehavior";
import { init as initButtonInGame, setup as setupButtonInGame } from "./behaviors/ButtonInGameBehavior";
import { init as initEndGameButton } from "./behaviors/EndGameButtonBehavior";
import { MoneyDisplay } from "./ui/MoneyDisplay";
import { init as initInformationText } from "./ui/InformationText";
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
import { init as initHudProgression } from "./behaviors/HudProgressionController";
import { init as initCostTextRotator } from "./ui/CostTextRotator";
import { MusicController } from "./audio/MusicController";
import { init as initAudioVisualizer } from "./ui/AudioVisualizer";
import { init as initNeonPipePulse } from "./ui/NeonPipePulse";

// Keep InGameUI (the persistent HUD + popups) alive across respawns. By default a
// ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
// references each behavior caches at startup — leaving ButtonMenu and the rest
// non-functional after death.
// The authoritative fix is `InGameUI.ResetOnSpawn = false` set directly on the
// ScreenGui in Studio (the idiomatic per-GUI Roblox flag). We also set the
// player-wide flag here as a belt-and-braces guard in case a future ScreenGui
// is added without thinking about its ResetOnSpawn.
StarterGui.ResetPlayerGuiOnSpawn = false;

initButtonInGame();
initEndGameButton();
MoneyDisplay.init();
initInformationText();
initRoomPrompts();
initOwnerIndicator();
initCommunityJoin();
initCommunityMascot();
initButtonMenu(setupButtonInGame);
initShopMenu();
initShopItems();
initShopMoneyBuy();
initBoostShop();
initMultiplierPass();
initMoneyBoost();
initRebirthMenu();
initRebirthController();
initHudProgression();
initCostTextRotator();
MusicController.init();
initAudioVisualizer();
initNeonPipePulse();
