import { MarketplaceService, Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { rebirthCost, rebirthMult } from "shared/ShopConfig";
import { SAFE_REBIRTH_PRODUCT_ID } from "shared/RebirthProducts";
import { FormatNumber } from "shared/NumberFormat";
import { InformationText } from "../ui/InformationText";

// Drives the Rebirth menu display (InGameUI/RebirthMenu) and the buy action.
// Read-only display fed by the replicated Money + Rebirths attributes; the buy
// button fires RebirthEvent when affordable, otherwise flashes the information
// panel. The server (RebirthService) re-validates, so the client guard here is
// purely for instant UX.

const player = Players.LocalPlayer;
const DENIED_COLOR = new Color3(1, 0.4, 0.4);

function getRebirths(): number {
	return (player.GetAttribute("Rebirths") as number | undefined) ?? 0;
}

function getMoney(): number {
	return (player.GetAttribute("Money") as number | undefined) ?? 0;
}

// "x2", "x3.5" below 1000 (2 decimals, trailing zeros trimmed) ; "x32.77K",
// "x2.1M" at and above 1000 — delegated to FormatNumber so the rebirth
// multiplier (8^R, e.g. ×2 097 152 at R7) never prints as a raw 7-9 digit
// number in a label sized for "x5".
function formatMult(value: number): string {
	if (value >= 1000) return `x${FormatNumber(value)}`;
	const hundredths = math.floor(value * 100 + 1e-7);
	const trimmed = hundredths % 100 === 0 ? tostring(hundredths / 100) : string.format("%.2f", hundredths / 100);
	return `x${trimmed}`;
}

export function init(): void {
	const menu = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI").WaitForChild("RebirthMenu");

	const info = menu.WaitForChild("RebirthInfoElements");
	const currentRebirth = info.WaitForChild("CurrentRebirth");
	const nextRebirth = info.WaitForChild("NextRebirth");
	const currentTitle = currentRebirth.WaitForChild("RebirthLevelTitle") as TextLabel;
	const currentMult = currentRebirth.WaitForChild("Frame").WaitForChild("MultiplierText") as TextLabel;
	const nextTitle = nextRebirth.WaitForChild("RebirthLevelTitle") as TextLabel;
	const nextMult = nextRebirth.WaitForChild("Frame").WaitForChild("MultiplierText") as TextLabel;

	const progressionBar = menu.WaitForChild("ProgressionBar");
	const fill = progressionBar.WaitForChild("CurrentProgressionFrame") as Frame;
	const moneyNeededText = progressionBar.WaitForChild("BackgroundFrame").WaitForChild("MoneyNeededText") as TextLabel;

	const buttonsFrame = menu.WaitForChild("ButtonsFrame");
	const buyButton = buttonsFrame.WaitForChild("RebirthButton").WaitForChild("Button") as GuiButton;
	const safeRebirthButton = buttonsFrame.WaitForChild("SafeRebirthButton").WaitForChild("Button") as GuiButton;

	function refresh(): void {
		const rebirths = getRebirths();
		const money = getMoney();
		const cost = rebirthCost(rebirths);

		currentTitle.Text = `Rebirth ${rebirths}`;
		nextTitle.Text = `Rebirth ${rebirths + 1}`;
		currentMult.Text = `${formatMult(rebirthMult(rebirths))} money`;
		nextMult.Text = `${formatMult(rebirthMult(rebirths + 1))} money`;

		const progress = math.clamp(money / cost, 0, 1);
		fill.Size = new UDim2(progress, 0, 1, 0);
		moneyNeededText.Text = `${FormatNumber(money)}/${FormatNumber(cost)}`;
	}

	buyButton.Activated.Connect(() => {
		if (getMoney() < rebirthCost(getRebirths())) {
			InformationText.show("Pas assez d'argent pour le Rebirth", { color: DENIED_COLOR });
			return;
		}
		Events.RebirthEvent.FireServer();
	});

	// Safe rebirth — paid Robux dev product. No in-game money gate (that's the point:
	// rebirth without losing any progression). The native purchase prompt shows the
	// price; on a successful receipt the server (RebirthService.safeRebirth) grants
	// +1 Rebirth while keeping Money + upgrades, and the menu refreshes on Rebirths.
	safeRebirthButton.Activated.Connect(() => {
		MarketplaceService.PromptProductPurchase(player, SAFE_REBIRTH_PRODUCT_ID);
	});

	player.GetAttributeChangedSignal("Money").Connect(refresh);
	player.GetAttributeChangedSignal("Rebirths").Connect(refresh);
	refresh();
}
