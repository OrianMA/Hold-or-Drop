import { Players } from "@rbxts/services";
import { InGameUIController } from "client/ui/InGameUIController";

// Opens / closes the Rebirth menu (InGameUI/RebirthMenu).
// The HUD button InGameUI/HUD/ButtonsFrame/RebirthFrame/ImageButton opens it; the
// CloseButton under RebirthMenu/CloseFrame closes it. Opening hides the
// persistent HUD; closing brings it back. Purely client-side — opening a menu
// needs no server authority (the actual rebirth purchase is validated
// server-side in RebirthService).

export function init(): void {
	const inGameUI = (Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const hud = inGameUI.WaitForChild("HUD"); // the persistent HUD frame
	const openButton = hud.WaitForChild("ButtonsFrame").WaitForChild("RebirthFrame").WaitForChild("ImageButton") as GuiButton;

	const rebirthMenu = inGameUI.WaitForChild("RebirthMenu") as GuiObject;
	const closeButton = rebirthMenu.WaitForChild("CloseFrame").WaitForChild("CloseButton") as GuiButton;

	rebirthMenu.Visible = false; // start hidden regardless of the Studio default

	openButton.Activated.Connect(() => {
		rebirthMenu.Visible = true;
		InGameUIController.disable();
	});
	closeButton.Activated.Connect(() => {
		rebirthMenu.Visible = false;
		InGameUIController.enable();
	});
}
