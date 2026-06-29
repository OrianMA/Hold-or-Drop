import { Players } from "@rbxts/services";

// Centralized control for the persistent HUD container.
// "HUD" here refers to a Frame (or other GuiObject) named "HUD" that sits
// INSIDE the InGameUI ScreenGui — sibling to the button-game popups (ButtonMenu,
// RocketLaunch, ButtonFinishGame). Toggling its Visible hides the HUD while
// keeping the popups rendering normally.

function getPlayerGui(): PlayerGui | undefined {
	return Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
}

// Walks PlayerGui descendants looking for the GuiObject named "HUD" — the
// persistent HUD frame nested inside the InGameUI ScreenGui.
function getHudFrame(): GuiObject | undefined {
	const playerGui = getPlayerGui();
	if (!playerGui) return undefined;
	for (const desc of playerGui.GetDescendants()) {
		if (desc.Name === "HUD" && desc.IsA("GuiObject")) return desc as GuiObject;
	}
	return undefined;
}

export const InGameUIController = {
	disable(): void {
		const frame = getHudFrame();
		if (frame) frame.Visible = false;
	},

	enable(): void {
		const frame = getHudFrame();
		if (frame) frame.Visible = true;
	},

	// MoneyParent lives inside the HUD frame. Recursive search lets it sit
	// anywhere under it.
	getMoneyParent(): GuiObject | undefined {
		const frame = getHudFrame();
		if (!frame) return undefined;
		const found = frame.FindFirstChild("MoneyParent", true);
		return found?.IsA("GuiObject") ? (found as GuiObject) : undefined;
	},
};
