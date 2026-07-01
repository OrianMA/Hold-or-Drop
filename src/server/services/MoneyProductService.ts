import { MarketplaceService, Players } from "@rbxts/services";
import { amountForProduct } from "shared/MoneyProducts";
import { levelGrantForProduct } from "shared/LevelProducts";
import { isSafeRebirthProduct } from "shared/RebirthProducts";
import { STATS } from "shared/ShopConfig";
import { PlayerDataService } from "./PlayerDataService";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { RebirthService } from "./RebirthService";

// Authoritative handler for ALL developer products. Owns the game's single
// MarketplaceService.ProcessReceipt callback. Two product families route through
// here:
//   • money packs (shared/MoneyProducts.ts)   → credit Money       (ShopMoneyBuy popup)
//   • progression products (shared/LevelProducts.ts) → add stat LEVELS (shop RobuxButtons)
//
// On a receipt we apply the matching grant and return PurchaseGranted. We return
// NotProcessedYet (Roblox retries later) when the buyer isn't in-game or their data
// is still loading (relevant attribute unset) — so a grant is never lost, nor
// written before/over a fresh load. Each grant is a synchronous attribute write
// immediately followed by the return, so there is no double-grant window and no
// DataStore receipt log is needed.

function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision {
	const player = Players.GetPlayerByUserId(receiptInfo.PlayerId);
	if (!player) return Enum.ProductPurchaseDecision.NotProcessedYet; // retry when they're back

	// Data still loading (PlayerDataService sets Money after its async load) — retry
	// so the grant isn't overwritten by the load.
	if (player.GetAttribute("Money") === undefined) return Enum.ProductPurchaseDecision.NotProcessedYet;

	const amount = amountForProduct(receiptInfo.ProductId);
	if (amount !== undefined) {
		PlayerDataService.add(player, "Money", amount);
		return Enum.ProductPurchaseDecision.PurchaseGranted;
	}

	const grant = levelGrantForProduct(receiptInfo.ProductId);
	if (grant !== undefined) {
		// Progression levels load after Money — retry until the stat's level attribute
		// exists so addLevel doesn't run before/over a fresh progression load.
		if (player.GetAttribute(STATS[grant.stat].levelAttribute) === undefined) {
			return Enum.ProductPurchaseDecision.NotProcessedYet;
		}
		// addLevel clamps to the stat's cap (e.g. Resistance) — a max-level buy is a no-op
		// gain but still granted (the client prevents prompting at the cap).
		PlayerProgressionService.addLevel(player, grant.stat, grant.levels);
		return Enum.ProductPurchaseDecision.PurchaseGranted;
	}

	if (isSafeRebirthProduct(receiptInfo.ProductId)) {
		// Safe rebirth increments Rebirths — guard on the Rebirths attribute (set by
		// PlayerProgressionService after its async load) so the grant never runs
		// before/over a fresh progression load and lands on the loaded count.
		if (player.GetAttribute("Rebirths") === undefined) return Enum.ProductPurchaseDecision.NotProcessedYet;
		RebirthService.safeRebirth(player);
		return Enum.ProductPurchaseDecision.PurchaseGranted;
	}

	warn(`MoneyProductService: unknown developer product ${receiptInfo.ProductId}`);
	return Enum.ProductPurchaseDecision.NotProcessedYet;
}

export const MoneyProductService = {
	init(): void {
		MarketplaceService.ProcessReceipt = processReceipt;
	},
};
