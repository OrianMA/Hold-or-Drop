import { IPopup } from "server/Interface/IPopup";

export class Popup implements IPopup {
	protected className = "";

	GetPlayerFrame(player: Player): Frame {
		const playerGui = player.WaitForChild("PlayerGui") as PlayerGui;
		const screenGui = playerGui.WaitForChild("InGameUI") as ScreenGui;
		const currentFrame = screenGui.WaitForChild(this.className) as Frame;

		return currentFrame;
	}

	Show(player: Player): void {
		this.GetPlayerFrame(player).Visible = true;
	}

	Hide(player: Player): void {
		this.GetPlayerFrame(player).Visible = false;
	}
}
