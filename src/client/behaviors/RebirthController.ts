import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { rebirthCost, rebirthMult } from "shared/ShopConfig";
import { FormatNumber } from "shared/NumberFormat";

// Binds the shop Rebirth panel (MainUI/ShopMenu/Body/RebirthPanel), which reuses
// the same frame structure as the upgrade items. Read-only display driven by the
// replicated Money + Rebirths attributes; the buy button fires RebirthEvent. The
// server re-validates, so the client guard here is purely for instant UX.

const player = Players.LocalPlayer;

function getRebirths(): number {
	return (player.GetAttribute("Rebirths") as number | undefined) ?? 0;
}

function getMoney(): number {
	return (player.GetAttribute("Money") as number | undefined) ?? 0;
}

// "×2", "×3.5" — trim trailing zeros.
function formatMult(value: number): string {
	const hundredths = math.floor(value * 100 + 1e-7);
	const trimmed = hundredths % 100 === 0 ? tostring(hundredths / 100) : string.format("%.2f", hundredths / 100);
	return `×${trimmed}`;
}

function setAffordable(button: TextButton, priceLabel: TextLabel, affordable: boolean): void {
	button.AutoButtonColor = affordable;
	button.BackgroundTransparency = affordable ? 0 : 0.6;
	priceLabel.TextTransparency = affordable ? 0 : 0.4;
}

export function init(): void {
	const mainUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("MainUI");
	const panel = mainUI.WaitForChild("ShopMenu").WaitForChild("Body").WaitForChild("RebirthPanel");

	const boost = panel.WaitForChild("BoostLyout");
	const titleText = boost.WaitForChild("BoostTitleText") as TextLabel;
	const currentText = boost.WaitForChild("CurrentStatFrame").WaitForChild("CurrentStatText") as TextLabel;
	const nextText = boost.WaitForChild("NextStatFrame").WaitForChild("NextStatText") as TextLabel;
	const buyButton = panel.WaitForChild("ButtonsLayout").WaitForChild("BuyButton") as TextButton;
	const priceLabel = buyButton.WaitForChild("TextLabel") as TextLabel;

	titleText.Text = "Rebirth";

	function refresh(): void {
		const rebirths = getRebirths();
		const cost = rebirthCost(rebirths);
		currentText.Text = formatMult(rebirthMult(rebirths));
		nextText.Text = formatMult(rebirthMult(rebirths + 1));
		priceLabel.Text = `${FormatNumber(cost)}$`;
		setAffordable(buyButton, priceLabel, getMoney() >= cost);
	}

	buyButton.Activated.Connect(() => {
		if (getMoney() < rebirthCost(getRebirths())) return; // server also guards
		Events.RebirthEvent.FireServer();
	});

	player.GetAttributeChangedSignal("Money").Connect(refresh);
	player.GetAttributeChangedSignal("Rebirths").Connect(refresh);
	refresh();
}
