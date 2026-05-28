import { init as initButtonMenu } from "./behaviors/ButtonMenuBehavior";
import { init as initButtonInGame, setup as setupButtonInGame } from "./behaviors/ButtonInGameBehavior";
import { init as initEndGameButton } from "./behaviors/EndGameButtonBehavior";
import { init as initMoneyDisplay } from "./ui/MoneyDisplay";

initButtonInGame();
initEndGameButton();
initMoneyDisplay();
initButtonMenu(setupButtonInGame);
