import { PopupType } from "shared/PopupType";
import { Popup } from "server/UI/Popup";

type PopupConfigEntry = { type: PopupType; class: new () => Popup };

let config: PopupConfigEntry[] = [];
const currentPopup = new Map<Player, PopupType>();

export const UiService = {
	init(popupConfig: PopupConfigEntry[]): void {
		config = popupConfig;
	},

	Show(player: Player, popupType: PopupType): void {
		const current = currentPopup.get(player);
		if (current !== undefined) this.FindPopup(current)?.Hide(player);

		currentPopup.set(player, popupType);
		this.FindPopup(popupType)?.Show(player);
	},

	Hide(player: Player, popupType: PopupType): void {
		this.FindPopup(popupType)?.Hide(player);
		if (currentPopup.get(player) === popupType) currentPopup.delete(player);
	},

	FindPopup(popupType: PopupType): Popup | undefined {
		const entry = config.find((c) => c.type === popupType);
		if (!entry) return undefined;
		return new entry.class() as unknown as Popup;
	},
};
