import { Players, Workspace } from "@rbxts/services";

// Opens / closes the Shop menu (MainUI/ShopMenu).
// The ProximityPrompt under Workspace/Shop/ProximityPromptPart opens it; the
// CloseButton under ShopMenu/header closes it. Purely client-side — opening a
// menu needs no server authority (purchases get validated server-side later).

const SHOP_MODEL = "Shop";
const PROMPT_PART = "ProximityPromptPart";
const SHOP_MENU = "ShopMenu";
const HEADER = "header";
const CLOSE_BUTTON = "CloseButton";

export function init(): void {
	const shop = Workspace.WaitForChild(SHOP_MODEL);
	const prompt = shop.WaitForChild(PROMPT_PART).WaitForChild("ProximityPrompt") as ProximityPrompt;

	const mainUI = (Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("MainUI");
	const shopMenu = mainUI.WaitForChild(SHOP_MENU) as GuiObject;
	const closeButton = shopMenu.WaitForChild(HEADER).WaitForChild(CLOSE_BUTTON) as GuiButton;

	shopMenu.Visible = false; // start hidden regardless of the Studio default

	prompt.Triggered.Connect(() => {
		shopMenu.Visible = true;
	});

	closeButton.Activated.Connect(() => {
		shopMenu.Visible = false;
	});
}
