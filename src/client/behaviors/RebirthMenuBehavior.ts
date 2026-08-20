import { Players } from "@rbxts/services";
import { InGameUIController } from "client/ui/InGameUIController";

// Opens / closes the Rebirth menu (InGameUI/RebirthMenu).
// The HUD button InGameUI/HUD/ButtonsFrame/RebirthFrame/ImageButton opens it, and so
// does the progression bar's RebirthButton once a rebirth is affordable (see
// HudProgressionController, which calls openRebirthMenu). The CloseButton under
// RebirthMenu/CloseFrame closes it. Opening hides the persistent HUD; closing brings
// it back. Purely client-side — opening a menu needs no server authority (the actual
// rebirth purchase is validated server-side in RebirthService).

let rebirthMenu: GuiObject | undefined;

// Shared by every entry point that opens the popup.
export function openRebirthMenu(): void {
	if (!rebirthMenu) return;
	rebirthMenu.Visible = true;
	InGameUIController.disable();
}

export function init(): void {
	const inGameUI = (Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const hud = inGameUI.WaitForChild("HUD"); // the persistent HUD frame
	const openButton = hud.WaitForChild("ButtonsFrame").WaitForChild("RebirthFrame").WaitForChild("ImageButton") as GuiButton;

	rebirthMenu = inGameUI.WaitForChild("RebirthMenu") as GuiObject;
	const closeButton = rebirthMenu.WaitForChild("CloseFrame").WaitForChild("CloseButton") as GuiButton;

	rebirthMenu.Visible = false; // start hidden regardless of the Studio default

	openButton.Activated.Connect(openRebirthMenu);
	closeButton.Activated.Connect(() => {
		if (rebirthMenu) rebirthMenu.Visible = false;
		InGameUIController.enable();
	});
}
