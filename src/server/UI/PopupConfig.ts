import { PopupType } from "../../shared/PopupType";
import { ButtonInGamePopup } from "./PopupBehaviors/ButtonInGamePopup";
import { ButtonMenuPopup } from "./PopupBehaviors/ButtonMenuPopup";

export const PopupConfig = [
	{ type: PopupType.ButtonMenu, frameName: "ButtonMenu", class: ButtonMenuPopup },
	{ type: PopupType.ButtonInGame, frameName: "ButtonInGame", class: ButtonInGamePopup },
];
