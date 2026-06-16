import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { rebirthCost, rebirthMult } from "shared/ShopConfig";
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

// "x2", "x3.5" — trim trailing zeros.
function formatMult(value: number): string {
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

	const buyButton = menu.WaitForChild("ButtonsFrame").WaitForChild("RebirthButton").WaitForChild("Button") as GuiButton;

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
			InformationText.show("Pas assez d'argent pour le Rebirth", DENIED_COLOR);
			return;
		}
		Events.RebirthEvent.FireServer();
	});

	player.GetAttributeChangedSignal("Money").Connect(refresh);
	player.GetAttributeChangedSignal("Rebirths").Connect(refresh);
	refresh();
}
