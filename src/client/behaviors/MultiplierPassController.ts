import { MarketplaceService, Players } from "@rbxts/services";
import { nextMoneyTier } from "shared/ShopConfig";

// Drives the HUD "buy multiplier pass" button
// (InGameUI/HUD/BottomList/MultiplierBuyButton). Always offers the NEXT money-tier
// game pass the player doesn't own yet — the MONEY_TIERS ladder in ShopBalance
// (×2, ×4, … ×1024) — read from the replicated MoneyTierMult attribute (resolved
// server-side by BoostService).
//   • BuyMultiplierPassFrame/RewardText                → "{mult}x Money"
//   • BuyMultiplierPassFrame/CostMovingText/CCCostText → raw Robux price (no K/M)
//   • TextButton                                       → PromptGamePassPurchase(id)
// After a purchase BoostService re-resolves ownership; MoneyTierMult changes and
// replicates, refreshing this to the next pass. When every tier is owned the whole
// button hides. Client-side only — ownership + the multiplier are server-authoritative.

const player = Players.LocalPlayer;

// Robux prices per game-pass id, cached to avoid repeat GetProductInfo web calls.
const priceCache = new Map<number, number>();

// The pass id currently offered — guards the async price write against the offered
// tier changing while a fetch is in flight.
let currentPassId = 0;

function moneyTierMult(): number {
	return (player.GetAttribute("MoneyTierMult") as number | undefined) ?? 1;
}

// Robux price of a pass (cached). undefined if the web call fails / no price set.
function fetchPrice(gamePassId: number): number | undefined {
	const cached = priceCache.get(gamePassId);
	if (cached !== undefined) return cached;
	const [ok, info] = pcall(() => MarketplaceService.GetProductInfo(gamePassId, Enum.InfoType.GamePass));
	if (ok && typeIs(info, "table")) {
		const price = (info as { PriceInRobux?: number }).PriceInRobux;
		if (price !== undefined) {
			priceCache.set(gamePassId, price);
			return price;
		}
	}
	return undefined;
}

export function init(): void {
	const buyButton = (player.WaitForChild("PlayerGui") as PlayerGui)
		.WaitForChild("InGameUI")
		.WaitForChild("HUD")
		.WaitForChild("BottomList")
		.WaitForChild("MultiplierBuyButton") as GuiObject;

	const textButton = buyButton.WaitForChild("TextButton") as GuiButton;
	const passFrame = buyButton.WaitForChild("BuyMultiplierPassFrame");
	const rewardText = passFrame.WaitForChild("RewardText") as TextLabel;
	const costText = passFrame.WaitForChild("CostMovingText").WaitForChild("CCCostText") as TextLabel;

	function updateDisplay(): void {
		const tier = nextMoneyTier(moneyTierMult());

		// Every tier owned — hide the whole button + text.
		if (!tier) {
			currentPassId = 0;
			buyButton.Visible = false;
			return;
		}

		buyButton.Visible = true;
		currentPassId = tier.gamePassId;
		rewardText.Text = `${tier.mult}x Money`;

		const cached = priceCache.get(tier.gamePassId);
		if (cached !== undefined) {
			costText.Text = tostring(cached);
		} else {
			costText.Text = "..."; // loading — avoids flashing a stale authored number
			task.spawn(() => {
				const price = fetchPrice(tier.gamePassId);
				// Only write if this tier is still the one on offer.
				if (price !== undefined && currentPassId === tier.gamePassId) {
					costText.Text = tostring(price);
				}
			});
		}
	}

	textButton.Activated.Connect(() => {
		if (currentPassId > 0) MarketplaceService.PromptGamePassPurchase(player, currentPassId);
	});

	player.GetAttributeChangedSignal("MoneyTierMult").Connect(updateDisplay);
	updateDisplay();
}
