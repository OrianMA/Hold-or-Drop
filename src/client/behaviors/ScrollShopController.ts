import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { FormatNumber } from "shared/NumberFormat";
import {
	SCROLL_SHOP_ITEMS,
	SCROLL_SHOP_OWNED_LABEL,
	ScrollShopItem,
	ScrollShopItemId,
	scrollShopItem,
} from "shared/ScrollShopConfig";
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
//
// Seule exception, purement visuelle : un objet à ACHAT UNIQUE déjà acquis affiche
// CLAIM à la place de son prix (et masque l'icône de token à côté). L'état vient de
// l'attribut répliqué déclaré par l'objet (`ownedAttribute`), donc l'affichage suit
// l'achat sans aller-retour et est correct dès la connexion.

const player = Players.LocalPlayer;

// Anti double-clic. Ne protège que de la répétition immédiate : la vraie garde est
// serveur.
const CLICK_DEBOUNCE = 0.4;

const SUCCESS_COLOR = new Color3(1, 0.85, 0.35);

interface Card {
	readonly item: ScrollShopItem;
	readonly priceText: TextLabel;
	// Icône de ScrollToken posée à côté du prix — masquée quand l'objet est acquis,
	// « CLAIM » n'étant pas un prix. Optionnelle : une carte sans icône reste valide.
	readonly priceIcon?: GuiObject;
	readonly button: GuiButton;
}

// Objet à achat unique déjà acquis ? Lit l'attribut que l'objet déclare lui-même.
function isOwned(item: ScrollShopItem): boolean {
	if (item.ownedAttribute === undefined) return false;
	return ((player.GetAttribute(item.ownedAttribute) as number | undefined) ?? 0) > 0;
}

// Résout une carte. FindFirstChild partout (jamais WaitForChild) : une Frame absente
// ou renommée coûte UNE carte, pas le blocage de tous les init clients suivants.
function readCard(scrollingFrame: Instance, item: ScrollShopItem): Card | undefined {
	const frame = scrollingFrame.FindFirstChild(item.frameName);
	const buyFrame = frame?.FindFirstChild("BuyButtonFrame");
	const displayFrame = buyFrame?.FindFirstChild("DisplayElementFrame");
	const priceText = displayFrame?.FindFirstChild("TextLabel");
	const priceIcon = displayFrame?.FindFirstChild("ScrollTokenImage");
	const button = buyFrame?.FindFirstChild("TextButton");

	if (!priceText?.IsA("TextLabel") || !button?.IsA("GuiButton")) {
		warn(`ScrollShopController: ${item.frameName} incomplet — objet ${item.id} non branché`);
		return undefined;
	}
	return { item, priceText, priceIcon: priceIcon?.IsA("GuiObject") ? priceIcon : undefined, button };
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

	// Le prix affiché vient TOUJOURS de la config, jamais du texte posé en Studio —
	// sauf pour un achat unique déjà acquis, qui affiche CLAIM sans son icône.
	const renderCard = (card: Card): void => {
		const owned = isOwned(card.item);
		card.priceText.Text = owned ? SCROLL_SHOP_OWNED_LABEL : FormatNumber(card.item.price);
		if (card.priceIcon) card.priceIcon.Visible = !owned;
	};

	let lastClick = 0;
	for (const card of cards) {
		renderCard(card);

		card.button.Activated.Connect(() => {
			// Déjà acquis : le serveur refuserait de toute façon, autant ne pas lui
			// envoyer un achat impossible ni faire clignoter un bandeau de refus.
			if (isOwned(card.item)) return;

			const now = os.clock();
			if (now - lastClick < CLICK_DEBOUNCE) return;
			lastClick = now;
			Events.ScrollShopPurchaseEvent.FireServer(card.item.id);
		});

		// L'attribut de possession est répliqué : la carte bascule sur CLAIM dès que le
		// serveur l'a posé, sans que l'achat ait besoin de la prévenir.
		if (card.item.ownedAttribute !== undefined) {
			player.GetAttributeChangedSignal(card.item.ownedAttribute).Connect(() => renderCard(card));
		}
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
