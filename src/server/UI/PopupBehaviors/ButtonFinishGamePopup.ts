import { Popup } from "../Popup";

// The popup itself is a thin Show/Hide wrapper around the ButtonFinishGame frame.
// All animation logic lives client-side (EndGameButtonBehavior) and is triggered
// by the server through Events.EndGameStartEvent after Show().
export class ButtonFinishGamePopup extends Popup {
	protected override className = "ButtonFinishGame";
}
