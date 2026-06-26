import { Players } from "@rbxts/services";

// Drives the HUD money-boost readout (InGameUI/HUD/BottomList/ProgressionBar/MoneyBoostText).
// Shows the money multiplier the player currently gets from money-tier game passes only —
// the MONEY_TIERS ladder resolved server-side by BoostService into the replicated
// MoneyTierMult attribute (the highest owned tier wins; defaults to 1 when none is owned).
//   • MoneyTierMult > 1 → "{mult}x money boost", text visible
//   • MoneyTierMult = 1 → no money-tier pass owned, hide the text
// Client-side display only — the multiplier is server-authoritative.

const player = Players.LocalPlayer;

function moneyTierMult(): number {
	return (player.GetAttribute("MoneyTierMult") as number | undefined) ?? 1;
}

export function init(): void {
	const boostText = (player.WaitForChild("PlayerGui") as PlayerGui)
		.WaitForChild("InGameUI")
		.WaitForChild("HUD")
		.WaitForChild("BottomList")
		.WaitForChild("ProgressionBar")
		.WaitForChild("MoneyBoostText") as TextLabel;

	function updateDisplay(): void {
		const mult = moneyTierMult();

		// No money-tier pass owned — hide the readout.
		if (mult <= 1) {
			boostText.Visible = false;
			return;
		}

		boostText.Visible = true;
		boostText.Text = `${mult}x money boost`;
	}

	player.GetAttributeChangedSignal("MoneyTierMult").Connect(updateDisplay);
	updateDisplay();
}
