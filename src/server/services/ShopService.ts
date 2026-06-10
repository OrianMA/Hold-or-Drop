import { Events } from "shared/Event";
import { ITEMS, ShopItemId, isAtCap, priceForItem } from "shared/ShopConfig";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { PlayerDataService } from "./PlayerDataService";

// Authoritative shop purchases. The client pre-checks affordability for instant
// feedback, but every purchase is fully re-validated here — never trust the
// client. Cash only; Robux buttons are not wired yet.

const DENIED_COLOR = new Color3(1, 0.4, 0.4);

function isShopItemId(value: unknown): value is ShopItemId {
	return typeIs(value, "string") && ITEMS[value as ShopItemId] !== undefined;
}

function handlePurchase(player: Player, itemId: unknown): void {
	if (!isShopItemId(itemId)) return;
	const item = ITEMS[itemId];

	const level = PlayerProgressionService.getLevel(player, item.stat);
	if (isAtCap(item.stat, level)) {
		Events.InformationTextEvent.FireClient(player, "Niveau maximum atteint", DENIED_COLOR);
		return;
	}

	const price = priceForItem(item, level);
	if (PlayerDataService.get(player, "Money") < price) {
		Events.InformationTextEvent.FireClient(player, "Pas assez d'argent", DENIED_COLOR);
		return;
	}

	PlayerDataService.add(player, "Money", -price);
	PlayerProgressionService.addLevel(player, item.stat, item.quantity);
}

export const ShopService = {
	init(): void {
		Events.ShopPurchaseEvent.OnServerEvent.Connect((player, itemId) => handlePurchase(player, itemId));
	},
};
