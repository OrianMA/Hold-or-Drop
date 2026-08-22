import { MarketplaceService, Players } from "@rbxts/services";
import { InGameUIController } from "client/ui/InGameUIController";
import { MONEY_PRODUCTS } from "shared/MoneyProducts";

// Opens / closes the "buy money with Robux" popup (InGameUI/ShopMoneyBuy) and
// wires its 9 product buttons to MarketplaceService developer-product prompts.
//   • Opened by MoneyParent/PlusButton/TextButton — celui du HUD, ET celui du
//     miroir InGameUI/MoneyParent affiché pendant le shop (§6.8) quand il existe :
//     les deux "+" sont le même bouton pour le joueur, il serait mort dans le miroir
//     s'il n'était pas branché lui aussi.
//   • Closed by ShopMoneyBuy/Header/CloseButtonFrame/CloseButton.
//   • Body/MoneyElement{n}/Button prompts MONEY_PRODUCTS[n-1].productId; the server
//     (MoneyProductService) credits the money on a successful receipt.
// Opening hides the persistent HUD (mirrors ShopBehavior); closing restores it.
// Purely client-side — the purchase + grant are validated server-side.

const SHOP_MONEY_BUY = "ShopMoneyBuy";

export function init(): void {
	const player = Players.LocalPlayer;
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");

	const popup = inGameUI.WaitForChild(SHOP_MONEY_BUY) as GuiObject;
	const closeButton = popup
		.WaitForChild("Header")
		.WaitForChild("CloseButtonFrame")
		.WaitForChild("CloseButton") as GuiButton;
	const body = popup.WaitForChild("Body");

	// L'ouvreur du HUD existe toujours : lui seul est attendu (WaitForChild).
	const openButton = inGameUI
		.WaitForChild("HUD")
		.WaitForChild("MoneyParent")
		.WaitForChild("PlusButton")
		.WaitForChild("TextButton") as GuiButton;

	// Le miroir affiché pendant le shop est OPTIONNEL (§6.8) : on le résout en
	// FindFirstChild, jamais en WaitForChild — les init clients sont séquentiels, un
	// yield infini ici tuerait tous les comportements enregistrés après celui-ci.
	const mirrorButton = inGameUI
		.FindFirstChild("MoneyParent")
		?.FindFirstChild("PlusButton")
		?.FindFirstChild("TextButton");

	popup.Visible = false; // start hidden regardless of the Studio default

	const open = (): void => {
		popup.Visible = true;
		InGameUIController.disable();
	};

	const close = (): void => {
		popup.Visible = false;
		InGameUIController.enable();
	};

	openButton.Activated.Connect(open);
	if (mirrorButton?.IsA("GuiButton")) mirrorButton.Activated.Connect(open);
	closeButton.Activated.Connect(close);

	// Wire each product button to prompt its developer product. Order matches the
	// GUI: MoneyElement{n} ↔ MONEY_PRODUCTS[n-1].
	MONEY_PRODUCTS.forEach((product, index) => {
		const button = body.WaitForChild(`MoneyElement${index + 1}`).WaitForChild("Button") as GuiButton;
		button.Activated.Connect(() => {
			MarketplaceService.PromptProductPurchase(player, product.productId);
		});
	});
}
