import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { ITEM_ORDER, ITEMS, ShopItem, STATS, isAtCap, priceForItem } from "shared/ShopConfig";
import { FormatNumber } from "shared/NumberFormat";

// Wires the four shop item frames (MainUI/ShopMenu/Body/*). Read-only display
// driven by replicated attributes (Money + the per-stat level attributes); the
// cash button fires ShopPurchaseEvent. The server re-validates every purchase,
// so the client guard here is purely for instant UX.
//
// Robux buttons (RobuxButton) are intentionally left untouched — not wired yet.

const player = Players.LocalPlayer;

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
	const buyButton = frame.WaitForChild("ButtonsLayout").WaitForChild("BuyButton") as TextButton;
	const priceLabel = buyButton.WaitForChild("TextLabel") as TextLabel;

	const cfg = STATS[item.stat];
	titleText.Text = item.title;

	function refresh(): void {
		const level = getLevel(cfg.levelAttribute);
		currentText.Text = cfg.display(cfg.valueFor(level));

		if (isAtCap(item.stat, level)) {
			nextText.Text = "MAX";
			priceLabel.Text = "MAX";
			setAffordable(buyButton, priceLabel, false);
			return;
		}

		nextText.Text = cfg.display(cfg.valueFor(level + item.quantity));
		const price = priceForItem(item, level);
		priceLabel.Text = `${FormatNumber(price)}$`;
		setAffordable(buyButton, priceLabel, getMoney() >= price);
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
	const mainUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("MainUI");
	const body = mainUI.WaitForChild("ShopMenu").WaitForChild("Body");

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
	player.GetAttributeChangedSignal("MultiplierLevel").Connect(refreshAll);
	player.GetAttributeChangedSignal("SafetyLevel").Connect(refreshAll);
}
