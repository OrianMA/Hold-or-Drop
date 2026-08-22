// ── Boutique ScrollToken (BuyRewardBody) ──────────────────────────────────────
// LE fichier de réglage des 6 achats payés en ScrollToken. Le prix écrit ici est
// la seule source de vérité : le serveur le débite, le client l'affiche dans
// `BuyButtonFrame/DisplayElementFrame/TextLabel`. Changer un prix ici le change
// partout, sans retoucher Studio.
//
// Les effets sont volontairement des VERBES connus du jeu (safe rebirth, +1 niveau
// de stat, événement Mega Rocket) — la boutique ne crée aucune mécanique nouvelle,
// elle en achète.

export type ScrollShopItemId =
	| "SafeRebirth"
	| "MoneyMultiplier"
	| "MegaRocket"
	| "RocketSpeed"
	| "BaseCash"
	| "Resistance";

export interface ScrollShopItem {
	readonly id: ScrollShopItemId;
	// Nom EXACT de la Frame dans QuestsPanel/BuyRewardBody/ScrollingFrame.
	readonly frameName: string;
	readonly price: number;
	// Achetable une seule fois par joueur (effet permanent).
	readonly oneShot?: boolean;
	// Bandeau affiché à l'acheteur après un achat validé. Le Mega Rocket n'en a pas :
	// il diffuse déjà son propre bandeau Legendary à TOUT le serveur (§6.24).
	readonly successText?: string;
}

// Le ×1.25 argent permanent. Additif comme les autres boosts d'argent (communauté,
// game-passes) : il ajoute +0.25 au facteur de boosts, qui est ensuite multiplié par
// MultRebirth — voir shared/ShopConfig.moneyMult et §6.6.
export const SCROLL_MONEY_BOOST = { mult: 1.25, attribute: "ScrollMoneyBoost" };

export const SCROLL_SHOP_ITEMS: readonly ScrollShopItem[] = [
	{
		id: "SafeRebirth",
		frameName: "ASafeRebirth",
		price: 350_000,
		successText: "Safe rebirth  +1 Rebirth, progression kept",
	},
	{
		id: "MoneyMultiplier",
		frameName: "BMoneyMultiplier",
		price: 250_000,
		oneShot: true,
		successText: "1.25x Money unlocked  permanent",
	},
	{ id: "MegaRocket", frameName: "CMegaRocket", price: 50_000 },
	{ id: "RocketSpeed", frameName: "DRocketSpeed", price: 15_000, successText: "+1 Rocket speed" },
	{ id: "BaseCash", frameName: "ERocketBaseCash", price: 20_000, successText: "+1 Base cash" },
	{ id: "Resistance", frameName: "FRocketResistance", price: 25_000, successText: "+1 Resistance" },
];

export function scrollShopItem(id: ScrollShopItemId): ScrollShopItem | undefined {
	for (const item of SCROLL_SHOP_ITEMS) {
		if (item.id === id) return item;
	}
	return undefined;
}

// Bandeau serveur-large quand un joueur paie l'événement Mega Rocket.
export function megaRocketPurchaseAnnounce(playerName: string): string {
	return `${playerName} triggered the MEGA ROCKET  CASH ×8`;
}
