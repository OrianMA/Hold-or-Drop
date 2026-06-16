import { Players, RunService, Workspace } from "@rbxts/services";
import { InGameUIController } from "client/ui/InGameUIController";

// Opens / closes the Shop menu (InGameUI/ShopMenu).
// The ProximityPrompt under Workspace/Shop/ProximityPromptPart opens it; the
// CloseButton under ShopMenu/Header closes it. Also auto-closes when the
// player walks more than CLOSE_DISTANCE studs away from the prompt part.
// Opening hides the persistent HUD; closing brings it back (every close path
// goes through close(), so the distance auto-close restores it too).
// Purely client-side — opening a menu needs no server authority (purchases
// get validated server-side later).

const SHOP_MODEL = "Shop";
const PROMPT_PART = "ProximityPromptPart";
const SHOP_MENU = "ShopMenu";
const HEADER = "Header";
const CLOSE_BUTTON = "CloseButton";
const CLOSE_DISTANCE = 15;

export function init(): void {
	const shop = Workspace.WaitForChild(SHOP_MODEL);
	const promptPart = shop.WaitForChild(PROMPT_PART) as BasePart;
	const prompt = promptPart.WaitForChild("ProximityPrompt") as ProximityPrompt;

	const inGameUI = (Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const shopMenu = inGameUI.WaitForChild(SHOP_MENU) as GuiObject;
	const closeButton = shopMenu.WaitForChild(HEADER).WaitForChild(CLOSE_BUTTON) as GuiButton;

	shopMenu.Visible = false; // start hidden regardless of the Studio default

	// Heartbeat watcher is only attached while the menu is open so the closed
	// state has zero per-frame cost.
	let distanceWatcher: RBXScriptConnection | undefined;

	const close = (): void => {
		shopMenu.Visible = false;
		InGameUIController.enable();
		distanceWatcher?.Disconnect();
		distanceWatcher = undefined;
	};

	const open = (): void => {
		shopMenu.Visible = true;
		InGameUIController.disable();
		distanceWatcher?.Disconnect();
		distanceWatcher = RunService.Heartbeat.Connect(() => {
			const root = Players.LocalPlayer.Character?.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
			if (!root) return;
			if (root.Position.sub(promptPart.Position).Magnitude > CLOSE_DISTANCE) close();
		});
	};

	prompt.Triggered.Connect(open);
	closeButton.Activated.Connect(close);
}
