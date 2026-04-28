import { PopupType } from "shared/PopupType";
import { PopupConfig } from "server/UI/PopupConfig";
import { Popup } from "server/UI/Popup";

export const UiService = {
	init() {},

	Show(player: Player, popupType: PopupType): void {
		this.FindPopup(popupType)?.Show(player);
	},

	Hide(player: Player, popupType: PopupType): void {
		this.FindPopup(popupType)?.Hide(player);
	},

	FindPopup(popupType: PopupType): Popup | undefined {
		const config = PopupConfig.find((c) => c.type === popupType);

		if (!config) return undefined;

		return new config.class() as unknown as Popup;
	},
};
