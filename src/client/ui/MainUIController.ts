import { Players } from "@rbxts/services";

// Centralized control for the persistent HUD container.
// "MainUI" here refers to a Frame (or other GuiObject) named "MainUI" that sits
// INSIDE the ScreenGui — sibling to the button-game popups (ButtonMenu,
// ButtonInGame, ButtonFinishGame). Toggling its Visible hides the HUD while
// keeping the popups rendering normally.

function getPlayerGui(): PlayerGui | undefined {
	return Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
}

// Walks PlayerGui descendants looking for a GuiObject called "MainUI" that
// isn't a ScreenGui (the ScreenGui ancestor is also commonly named MainUI).
function getMainUIFrame(): GuiObject | undefined {
	const playerGui = getPlayerGui();
	if (!playerGui) return undefined;
	for (const desc of playerGui.GetDescendants()) {
		if (desc.Name === "MainUI" && desc.IsA("GuiObject")) return desc as GuiObject;
	}
	return undefined;
}

export const MainUIController = {
	disable(): void {
		const frame = getMainUIFrame();
		if (frame) frame.Visible = false;
	},

	enable(): void {
		const frame = getMainUIFrame();
		if (frame) frame.Visible = true;
	},

	// MoneyParent lives inside the MainUI frame. Recursive search lets it sit
	// anywhere under it.
	getMoneyParent(): GuiObject | undefined {
		const frame = getMainUIFrame();
		if (!frame) return undefined;
		const found = frame.FindFirstChild("MoneyParent", true);
		return found?.IsA("GuiObject") ? (found as GuiObject) : undefined;
	},
};
