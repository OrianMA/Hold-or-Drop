import { PopupType } from "shared/PopupType";
import { Popup } from "server/UI/Popup";

type PopupConfigEntry = { type: PopupType; class: new () => Popup };

let config: PopupConfigEntry[] = [];
const currentPopup = new Map<Player, PopupType>();

// Notified just before ANY popup other than ButtonFinishGame opens. Used by
// EndGameButtonModule to drop a pending end-game payout (see its flush()) so the finish
// screen never pops over whatever the player just opened. A registered callback rather
// than a direct import — UiService must not depend on the gameplay modules.
let onBeforeShow: ((player: Player, popupType: PopupType) => void) | undefined;

export const UiService = {
	init(popupConfig: PopupConfigEntry[]): void {
		config = popupConfig;
	},

	SetBeforeShow(callback: (player: Player, popupType: PopupType) => void): void {
		onBeforeShow = callback;
	},

	Show(player: Player, popupType: PopupType): void {
		if (onBeforeShow && popupType !== PopupType.ButtonFinishGame) onBeforeShow(player, popupType);

		const current = currentPopup.get(player);
		if (current !== undefined) this.FindPopup(current)?.Hide(player);

		currentPopup.set(player, popupType);
		this.FindPopup(popupType)?.Show(player);
	},

	Hide(player: Player, popupType: PopupType): void {
		this.FindPopup(popupType)?.Hide(player);
		if (currentPopup.get(player) === popupType) currentPopup.delete(player);
	},

	HideCurrent(player: Player): void {
		const current = currentPopup.get(player);
		if (current !== undefined) this.Hide(player, current);
	},

	FindPopup(popupType: PopupType): Popup | undefined {
		const entry = config.find((c) => c.type === popupType);
		if (!entry) return undefined;
		return new entry.class() as unknown as Popup;
	},
};
