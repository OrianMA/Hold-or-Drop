import { PopupType } from "../../shared/PopupType";
import { RocketLaunchPopup } from "./PopupBehaviors/RocketLaunchPopup";
import { ButtonMenuPopup } from "./PopupBehaviors/ButtonMenuPopup";
import { ButtonFinishGamePopup } from "./PopupBehaviors/ButtonFinishGamePopup";

export const PopupConfig = [
	{ type: PopupType.ButtonMenu, frameName: "ButtonMenu", class: ButtonMenuPopup },
	{ type: PopupType.RocketLaunch, frameName: "RocketLaunch", class: RocketLaunchPopup },
	{ type: PopupType.ButtonFinishGame, frameName: "ButtonFinishGame", class: ButtonFinishGamePopup },
];
