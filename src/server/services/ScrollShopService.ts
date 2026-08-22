import { Events } from "shared/Event";
import { isAtCap } from "shared/ShopConfig";
import {
	SCROLL_MONEY_BOOST,
	ScrollShopItem,
	ScrollShopItemId,
	megaRocketPurchaseAnnounce,
	scrollShopItem,
} from "shared/ScrollShopConfig";
import { PlayerDataService } from "./PlayerDataService";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { MegaRocketService } from "./MegaRocketService";
import { AnalyticsService } from "./AnalyticsService";

// Autorité de la boutique ScrollToken (§6.27) — le pendant de ShopService pour la
// seconde monnaie. Même discipline : le client pré-affiche les prix pour un retour
// immédiat, mais RIEN n'est décidé côté client. Ici on revalide le solde, l'unicité
// et le plafond de stat, puis on débite et on applique l'effet.
//
// Les effets ne sont que des appels aux systèmes existants (safe rebirth, +1 niveau,
// événement Mega Rocket) : la boutique n'invente aucune mécanique.

const DENIED_COLOR = new Color3(1, 0.4, 0.4);

function deny(player: Player, message: string): void {
	Events.InformationTextEvent.FireClient(player, message, { color: DENIED_COLOR });
}

// Objet à achat unique déjà acquis ? Lit l'attribut déclaré par l'objet lui-même.
function isOwned(player: Player, item: ScrollShopItem): boolean {
	if (item.ownedAttribute === undefined) return false;
	return PlayerDataService.get(player, item.ownedAttribute as "ScrollMoneyBoost") > 0;
}

// Applique l'effet. Retourne false quand l'achat doit être REFUSÉ (déjà possédé,
// stat au plafond…) — le débit n'a alors pas lieu.
function applyEffect(player: Player, item: ScrollShopItem): boolean {
	if (item.id === "SafeRebirth") {
		// Exactement le safe rebirth du produit Robux : +1 rebirth, aucun niveau perdu,
		// argent intact (§6.9).
		PlayerProgressionService.safeRebirth(player);
		return true;
	}

	if (item.id === "MoneyMultiplier") {
		PlayerDataService.set(player, SCROLL_MONEY_BOOST.attribute as "ScrollMoneyBoost", 1);
		// Le boost entre dans MoneyMult / EffectiveBaseCash — il faut re-dériver tout de
		// suite, sinon il ne s'appliquerait qu'à la prochaine recompute.
		PlayerProgressionService.recompute(player);
		return true;
	}

	if (item.id === "MegaRocket") {
		MegaRocketService.fireNow(megaRocketPurchaseAnnounce(player.DisplayName));
		return true;
	}

	// Les trois derniers sont des +1 niveau de stat, payés en tokens au lieu du cash.
	const stat = item.id; // "RocketSpeed" | "BaseCash" | "Resistance"
	if (isAtCap(stat, PlayerProgressionService.getLevel(player, stat))) {
		deny(player, "Max level reached");
		return false;
	}
	PlayerProgressionService.addLevel(player, stat, 1);
	return true;
}

function handlePurchase(player: Player, itemId: unknown): void {
	if (!typeIs(itemId, "string")) return;
	const item = scrollShopItem(itemId as ScrollShopItemId);
	if (!item) return;

	if (isOwned(player, item)) {
		deny(player, "Already owned");
		return;
	}

	const balance = PlayerDataService.get(player, "ScrollTokens");
	if (balance < item.price) {
		deny(player, "Not enough tokens");
		return;
	}

	// L'effet passe AVANT le débit : un refus tardif (stat au plafond) ne doit jamais
	// coûter de tokens au joueur.
	if (!applyEffect(player, item)) return;

	PlayerDataService.add(player, "ScrollTokens", -item.price);
	Events.ScrollShopPurchasedEvent.FireClient(player, item.id, item.price);
	AnalyticsService.custom(player, "ScrollShopPurchase", item.price, item.id);
}

export const ScrollShopService = {
	init(): void {
		Events.ScrollShopPurchaseEvent.OnServerEvent.Connect((player, itemId) => handlePurchase(player, itemId));
	},
};
