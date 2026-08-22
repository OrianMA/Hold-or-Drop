import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { FormatNumber } from "shared/NumberFormat";
import { SCROLL_SHOP_ITEMS, ScrollShopItem, ScrollShopItemId, scrollShopItem } from "shared/ScrollShopConfig";
import { ScrollTokenDisplay } from "client/ui/ScrollTokenDisplay";
import { InformationText } from "client/ui/InformationText";

// Boutique ScrollToken (QuestsPanel/BuyRewardBody) — le pendant client de
// ScrollShopService. Deux responsabilités, rien de plus :
//   • écrire le PRIX de chaque carte depuis shared/ScrollShopConfig, pour qu'un
//     changement de prix se voie sans retoucher Studio ;
//   • envoyer l'intention d'achat et jouer le retour visuel quand le serveur confirme.
//
// L'achat est immédiat (pas de confirmation) : le serveur revalide solde, unicité et
// plafond, débite, applique l'effet, puis répond par ScrollShopPurchasedEvent. Un
// refus arrive en bandeau rouge via InformationTextEvent — il n'y a donc AUCUNE
// pré-validation ici : le client ne connaît pas les règles, il ne les devine pas.

const player = Players.LocalPlayer;

// Anti double-clic. Ne protège que de la répétition immédiate : la vraie garde est
// serveur.
const CLICK_DEBOUNCE = 0.4;

const SUCCESS_COLOR = new Color3(1, 0.85, 0.35);

interface Card {
	readonly item: ScrollShopItem;
	readonly priceText: TextLabel;
	readonly button: GuiButton;
}

// Résout une carte. FindFirstChild partout (jamais WaitForChild) : une Frame absente
// ou renommée coûte UNE carte, pas le blocage de tous les init clients suivants.
function readCard(scrollingFrame: Instance, item: ScrollShopItem): Card | undefined {
	const frame = scrollingFrame.FindFirstChild(item.frameName);
	const buyFrame = frame?.FindFirstChild("BuyButtonFrame");
	const priceText = buyFrame?.FindFirstChild("DisplayElementFrame")?.FindFirstChild("TextLabel");
	const button = buyFrame?.FindFirstChild("TextButton");

	if (!priceText?.IsA("TextLabel") || !button?.IsA("GuiButton")) {
		warn(`ScrollShopController: ${item.frameName} incomplet — objet ${item.id} non branché`);
		return undefined;
	}
	return { item, priceText, button };
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const body = inGameUI.WaitForChild("QuestsPanel").WaitForChild("BuyRewardBody");
	const scrollingFrame = body.WaitForChild("ScrollingFrame");

	const cards: Card[] = [];
	for (const item of SCROLL_SHOP_ITEMS) {
		const card = readCard(scrollingFrame, item);
		if (card) cards.push(card);
	}

	let lastClick = 0;
	for (const card of cards) {
		// Le prix affiché vient TOUJOURS de la config, jamais du texte posé en Studio.
		card.priceText.Text = FormatNumber(card.item.price);

		card.button.Activated.Connect(() => {
			const now = os.clock();
			if (now - lastClick < CLICK_DEBOUNCE) return;
			lastClick = now;
			Events.ScrollShopPurchaseEvent.FireServer(card.item.id);
		});
	}

	// Achat confirmé : les tokens sont déjà débités côté serveur et l'attribut a déjà
	// bougé — il ne reste que la lecture de la dépense et le bandeau de l'objet.
	// Le Mega Rocket n'a pas de bandeau propre : il diffuse déjà le sien à tout le
	// serveur (§6.24), en dire plus ferait doublon.
	Events.ScrollShopPurchasedEvent.OnClientEvent.Connect((id: ScrollShopItemId, price: number) => {
		ScrollTokenDisplay.spend(price);
		const item = scrollShopItem(id);
		if (item?.successText !== undefined) {
			InformationText.show(item.successText, { rarity: "Rare", color: SUCCESS_COLOR });
		}
	});
}
