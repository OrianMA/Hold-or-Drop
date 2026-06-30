import { MarketplaceService, Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { ITEM_ORDER, ITEMS, ShopItem, STATS, isAtCap, priceForItem } from "shared/ShopConfig";
import { levelProductForStat } from "shared/LevelProducts";
import { FormatNumber } from "shared/NumberFormat";
import { InformationText } from "client/ui/InformationText";

// Wires the four shop item frames (InGameUI/ShopMenu/Body/*). Read-only display
// driven by replicated attributes (Money + the per-stat level attributes); the
// cash BuyButton fires ShopPurchaseEvent, the RobuxButton prompts a developer
// product (shared/LevelProducts.ts). The server re-validates every purchase, so
// the client guards here are purely for instant UX.

const player = Players.LocalPlayer;
const DENIED_COLOR = new Color3(1, 0.4, 0.4);

// Robux price per dev product (GetProductInfo is a web call — fetch once, cache).
const robuxPriceCache = new Map<number, number>();
function fetchRobuxPrice(productId: number, label: TextLabel): void {
	const cached = robuxPriceCache.get(productId);
	if (cached !== undefined) {
		label.Text = tostring(cached);
		return;
	}
	task.spawn(() => {
		const [ok, info] = pcall(() => MarketplaceService.GetProductInfo(productId, Enum.InfoType.Product));
		if (ok && typeIs(info, "table")) {
			const price = (info as { PriceInRobux?: number }).PriceInRobux ?? 0;
			robuxPriceCache.set(productId, price);
			label.Text = tostring(price);
		}
	});
}

function getLevel(levelAttribute: string): number {
	return (player.GetAttribute(levelAttribute) as number | undefined) ?? 0;
}

function getMoney(): number {
	return (player.GetAttribute("Money") as number | undefined) ?? 0;
}

// Cosmetic only — the real gate is the handler guard + server validation.
function setAffordable(button: TextButton, priceLabel: TextLabel, affordable: boolean): void {
	button.AutoButtonColor = affordable;
	button.BackgroundTransparency = affordable ? 0 : 0.6;
	priceLabel.TextTransparency = affordable ? 0 : 0.4;
}

// Returns a refresh closure that re-renders the frame from current attributes.
function bindItem(body: Instance, item: ShopItem): () => void {
	const frame = body.WaitForChild(item.frameName);
	const boost = frame.WaitForChild("BoostLyout");
	const titleText = boost.WaitForChild("BoostTitleText") as TextLabel;
	const currentText = boost.WaitForChild("CurrentStatFrame").WaitForChild("CurrentStatText") as TextLabel;
	const nextText = boost.WaitForChild("NextStatFrame").WaitForChild("NextStatText") as TextLabel;
	const buttons = frame.WaitForChild("ButtonsLayout");
	const buyButton = buttons.WaitForChild("BuyButton") as TextButton;
	const priceLabel = buyButton.WaitForChild("TextLabel") as TextLabel;

	const cfg = STATS[item.stat];
	titleText.Text = item.title;

	// Robux dev product (grants `levels` of this stat). Same product backs both
	// BaseCash frames (+1 and +5) via the shared stat.
	const robuxButton = buttons.WaitForChild("RobuxButton") as TextButton;
	const robuxGainLabel = robuxButton.WaitForChild("GainQuantityText") as TextLabel;
	const robuxPriceLabel = robuxButton.WaitForChild("RobuxQuantityText") as TextLabel;
	const product = levelProductForStat(item.stat);
	if (product) {
		robuxGainLabel.Text = `+${product.levels} niv.`;
		fetchRobuxPrice(product.productId, robuxPriceLabel);
		robuxButton.Activated.Connect(() => {
			// Refuse at the cap (Safety): no prompt, just inform the player.
			if (isAtCap(item.stat, getLevel(cfg.levelAttribute))) {
				InformationText.show("Niveau maximum atteint", DENIED_COLOR);
				return;
			}
			MarketplaceService.PromptProductPurchase(player, product.productId);
		});
	}

	function refresh(): void {
		const level = getLevel(cfg.levelAttribute);
		currentText.Text = cfg.display(cfg.valueFor(level));

		if (isAtCap(item.stat, level)) {
			nextText.Text = "MAX";
			priceLabel.Text = "MAX";
			setAffordable(buyButton, priceLabel, false);
			// Grey the Robux button too — it refuses the purchase at the cap.
			if (product) {
				robuxGainLabel.Text = "MAX";
				robuxButton.AutoButtonColor = false;
				robuxButton.BackgroundTransparency = 0.6;
			}
			return;
		}

		nextText.Text = cfg.display(cfg.valueFor(level + item.quantity));
		const price = priceForItem(item, level);
		priceLabel.Text = `${FormatNumber(price)}$`;
		setAffordable(buyButton, priceLabel, getMoney() >= price);
		// Restore the Robux button (e.g. Safety dropped back below cap on rebirth).
		if (product) {
			robuxGainLabel.Text = `+${product.levels} niv.`;
			robuxButton.AutoButtonColor = true;
			robuxButton.BackgroundTransparency = 0;
		}
	}

	buyButton.Activated.Connect(() => {
		const level = getLevel(cfg.levelAttribute);
		if (isAtCap(item.stat, level)) return;
		if (getMoney() < priceForItem(item, level)) return; // server also guards
		Events.ShopPurchaseEvent.FireServer(item.id);
	});

	refresh();
	return refresh;
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const body = inGameUI.WaitForChild("ShopMenu").WaitForChild("Body");

	const refreshers: Array<() => void> = [];
	for (const id of ITEM_ORDER) {
		refreshers.push(bindItem(body, ITEMS[id]));
	}

	const refreshAll = (): void => {
		for (const refresh of refreshers) refresh();
	};

	// Money affects every item's affordability; each level attribute changes the
	// stat display + next price. Refresh everything on any of them for simplicity.
	player.GetAttributeChangedSignal("Money").Connect(refreshAll);
	player.GetAttributeChangedSignal("BaseCashLevel").Connect(refreshAll);
	player.GetAttributeChangedSignal("RocketSpeedLevel").Connect(refreshAll);
	player.GetAttributeChangedSignal("SafetyLevel").Connect(refreshAll);
}
