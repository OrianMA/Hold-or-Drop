import { Events } from "shared/Event";
import { UiService } from "server/services/UiService";
import { PopupType } from "shared/PopupType";
import { Popup } from "../Popup";

export class ButtonMenuPopup extends Popup {
	protected override className = "ButtonMenu";

	override Show(player: Player): void {
		super.Show(player);

		const connection = Events.StartButtonClickedEvent.OnServerEvent.Connect((firingPlayer) => {
			if (firingPlayer !== player) return;
			connection.Disconnect();
			UiService.Show(player, PopupType.ButtonInGame);
		});
	}
}
