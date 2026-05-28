import { PopupType } from "../../shared/PopupType";
import { ButtonInGamePopup } from "./PopupBehaviors/ButtonInGamePopup";
import { ButtonMenuPopup } from "./PopupBehaviors/ButtonMenuPopup";
import { ButtonFinishGamePopup } from "./PopupBehaviors/ButtonFinishGamePopup";

export const PopupConfig = [
	{ type: PopupType.ButtonMenu, frameName: "ButtonMenu", class: ButtonMenuPopup },
	{ type: PopupType.ButtonInGame, frameName: "ButtonInGame", class: ButtonInGamePopup },
	{ type: PopupType.ButtonFinishGame, frameName: "ButtonFinishGame", class: ButtonFinishGamePopup },
];
