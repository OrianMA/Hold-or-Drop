import { Popup } from "../Popup";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { startButtonGame } from "server/modules/ButtonInGameModule";

export class ButtonInGamePopup extends Popup {
	protected override className = "ButtonInGame";

	override Show(player: Player): void {
		super.Show(player);

		const session = ButtonSessionService.getSession(player);
		if (!session) {
			warn(`ButtonInGamePopup: No session found for ${player.Name}`);
			return;
		}

		startButtonGame(player, session);
	}
}
