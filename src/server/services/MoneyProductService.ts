import { MarketplaceService, Players } from "@rbxts/services";
import { amountForProduct } from "shared/MoneyProducts";
import { PlayerDataService } from "./PlayerDataService";

// Authoritative handler for the Robux "buy money" developer products (the 9 packs
// in the ShopMoneyBuy popup). Owns the game's single MarketplaceService.ProcessReceipt
// callback — route any future developer products through here.
//
// On a receipt we credit the mapped amount to the buyer's Money and return
// PurchaseGranted. We return NotProcessedYet (Roblox retries later) when the buyer
// isn't in-game or their data is still loading (Money attribute unset) — so a grant
// is never lost, nor written before/over a fresh load. The grant is a synchronous
// attribute write immediately followed by the return, so there is no double-grant
// window and no DataStore receipt log is needed.

function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision {
	const player = Players.GetPlayerByUserId(receiptInfo.PlayerId);
	if (!player) return Enum.ProductPurchaseDecision.NotProcessedYet; // retry when they're back

	// Data still loading (PlayerDataService sets Money after its async load) — retry
	// so the grant isn't overwritten by the load.
	if (player.GetAttribute("Money") === undefined) return Enum.ProductPurchaseDecision.NotProcessedYet;

	const amount = amountForProduct(receiptInfo.ProductId);
	if (amount === undefined) {
		warn(`MoneyProductService: unknown developer product ${receiptInfo.ProductId}`);
		return Enum.ProductPurchaseDecision.NotProcessedYet;
	}

	PlayerDataService.add(player, "Money", amount);
	return Enum.ProductPurchaseDecision.PurchaseGranted;
}

export const MoneyProductService = {
	init(): void {
		MarketplaceService.ProcessReceipt = processReceipt;
	},
};
