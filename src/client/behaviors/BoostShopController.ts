import { MarketplaceService, Players } from "@rbxts/services";
import { SAFETY_PASS } from "shared/ShopBalance";
import { nextMoneyTier } from "shared/ShopConfig";
import { InformationText } from "client/ui/InformationText";

// Shop "boosts" UI — read-only multiplier readout + two Robux upsell buttons.
// Pure display from replicated attributes (MultRebirth / InCommunity /
// MoneyTierMult / MoneyMult); the buttons prompt a game-pass purchase. A pass
// whose id is 0 is INERT: the button shows a "soon" state and does nothing.
// Community is claimed in-world via the CommunityJoinPart prompt, not here.

const player = Players.LocalPlayer;
const SOON_COLOR = new Color3(1, 0.85, 0.4);

function num(attr: string, fallback: number): number {
	return (player.GetAttribute(attr) as number | undefined) ?? fallback;
}

// "×6", "×3.5" — trim trailing zeros.
function fmtMult(value: number): string {
	const hundredths = math.floor(value * 100 + 1e-7);
	const trimmed = hundredths % 100 === 0 ? tostring(hundredths / 100) : string.format("%.2f", hundredths / 100);
	return `×${trimmed}`;
}

// Resolves RobuxButton/GainQuantityText if present (label of the gained boost).
function gainLabel(robux: Instance): TextLabel | undefined {
	const found = robux.FindFirstChild("GainQuantityText");
	return found && found.IsA("TextLabel") ? found : undefined;
}

// Wires a RobuxButton to prompt `gamePassId`; inert (with a "soon" gain label)
// when the id is 0. `gainText` is the boost it grants (e.g. "×4", "+20% safety").
function bindRobux(robux: TextButton, gamePassId: number, gainText: string): void {
	const label = gainLabel(robux);
	if (label) {
		label.Text = gamePassId > 0 ? gainText : "Bientôt";
		if (gamePassId <= 0) label.TextColor3 = SOON_COLOR;
	}
	robux.Activated.Connect(() => {
		if (gamePassId <= 0) {
			InformationText.show("Bientôt disponible", SOON_COLOR);
			return;
		}
		MarketplaceService.PromptGamePassPurchase(player, gamePassId);
	});
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const shop = inGameUI.WaitForChild("ShopMenu");
	const body = shop.WaitForChild("Body");

	const readout = shop.WaitForChild("Header").WaitForChild("MultiplierText") as TextLabel;

	const moneyRobux = body
		.WaitForChild("AButtonMoney")
		.WaitForChild("ButtonsLayout")
		.WaitForChild("RobuxButton") as TextButton;
	const safetyRobux = body
		.WaitForChild("DSafety")
		.WaitForChild("ButtonsLayout")
		.WaitForChild("RobuxButton") as TextButton;

	// Money-tier upsell: show the NEXT tier above what the player owns.
	const tierMult = num("MoneyTierMult", 1);
	const nextTier = nextMoneyTier(tierMult);
	bindRobux(moneyRobux, nextTier ? nextTier.gamePassId : 0, nextTier ? fmtMult(nextTier.mult) : "MAX");

	// Safety pass: flat +20% (the pass id; inert at 0).
	bindRobux(safetyRobux, SAFETY_PASS.gamePassId, "+20% safety");

	function refresh(): void {
		const rebirth = num("MultRebirth", 1);
		const tier = num("MoneyTierMult", 1);
		const inCommunity = player.GetAttribute("InCommunity") === true;
		const total = num("MoneyMult", 1);
		const community = inCommunity ? "×2" : "×1";
		readout.Text = `Money ${fmtMult(total)} (Rebirth ${fmtMult(rebirth)} · Communauté ${community} · Palier ${fmtMult(tier)})`;
	}

	player.GetAttributeChangedSignal("MoneyMult").Connect(refresh);
	player.GetAttributeChangedSignal("MultRebirth").Connect(refresh);
	player.GetAttributeChangedSignal("MoneyTierMult").Connect(refresh);
	player.GetAttributeChangedSignal("InCommunity").Connect(refresh);
	refresh();
}
