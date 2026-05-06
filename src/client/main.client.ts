import { init as initButtonMenu } from "./behaviors/ButtonMenuBehavior";
import { init as initButtonInGame, setup as setupButtonInGame } from "./behaviors/ButtonInGameBehavior";

initButtonInGame();
initButtonMenu(setupButtonInGame);
