import { Events } from "shared/Event";
import { UiService } from "server/services/UiService";
import { PopupType } from "shared/PopupType";
import { endButtonGame } from "server/modules/ButtonInGameModule";
import { Popup } from "../Popup";

export class ButtonMenuPopup extends Popup {
	protected override className = "ButtonMenu";

	override Show(player: Player): void {
		super.Show(player);

		const startConn = Events.StartButtonClickedEvent.OnServerEvent.Connect((p) => {
			if (p !== player) return;
			startConn.Disconnect();
			quitConn.Disconnect();
			UiService.Show(player, PopupType.ButtonInGame);
		});

		const quitConn = Events.QuitButtonClickedEvent.OnServerEvent.Connect((p) => {
			if (p !== player) return;
			startConn.Disconnect();
			quitConn.Disconnect();
			endButtonGame(player);
		});
	}
}
