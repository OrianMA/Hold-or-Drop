import { StarterGui } from "@rbxts/services";
import { init as initButtonMenu } from "./behaviors/ButtonMenuBehavior";
import { init as initButtonInGame, setup as setupButtonInGame } from "./behaviors/ButtonInGameBehavior";
import { init as initEndGameButton } from "./behaviors/EndGameButtonBehavior";
import { MoneyDisplay } from "./ui/MoneyDisplay";
import { init as initInformationText } from "./ui/InformationText";
import { init as initRoomPrompts } from "./rooms/RoomPromptController";
import { init as initOwnerIndicator } from "./rooms/OwnerIndicatorController";
import { init as initShopMenu } from "./behaviors/ShopBehavior";

// Keep MainUI (the persistent HUD + popups) alive across respawns. By default a
// ScreenGui resets on spawn, so dying would wipe PlayerGui and invalidate the
// references each behavior caches at startup — leaving ButtonMenu and the rest
// non-functional after death.
// The authoritative fix is `MainUI.ResetOnSpawn = false` set directly on the
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
initButtonMenu(setupButtonInGame);
initShopMenu();
