import { Players } from "@rbxts/services";
import { COMMUNITY } from "shared/ShopBalance";

// Shop "boosts" UI — read-only multiplier readout in the ShopMenu header. Pure
// display from replicated attributes (MultRebirth / InCommunity / MoneyTierMult /
// MoneyMult). The shop RobuxButtons are wired by ShopItemsController (developer
// products); the money-tier game-pass upsell lives on the HUD MultiplierBuyButton
// (MultiplierPassController), and Community is claimed via the CommunityJoinPart
// prompt — none of that is handled here anymore.

const player = Players.LocalPlayer;

function num(attr: string, fallback: number): number {
	return (player.GetAttribute(attr) as number | undefined) ?? fallback;
}

// "×6", "×3.5" — trim trailing zeros.
function fmtMult(value: number): string {
	const hundredths = math.floor(value * 100 + 1e-7);
	const trimmed = hundredths % 100 === 0 ? tostring(hundredths / 100) : string.format("%.2f", hundredths / 100);
	return `×${trimmed}`;
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");
	const shop = inGameUI.WaitForChild("ShopMenu");

	const readout = shop.WaitForChild("Header").WaitForChild("MultiplierText") as TextLabel;

	function refresh(): void {
		const rebirth = num("MultRebirth", 1);
		const tier = num("MoneyTierMult", 1);
		const inCommunity = player.GetAttribute("InCommunity") === true;
		const total = num("MoneyMult", 1);
		// Le rebirth MULTIPLIE le facteur de boost ; la communauté et le palier
		// s'additionnent à l'intérieur de ce facteur (voir ShopConfig.moneyMult).
		const boosts = 1 + (inCommunity ? COMMUNITY.mult - 1 : 0) + (tier - 1);
		readout.Text = `Money ${fmtMult(total)} (Rebirth ${fmtMult(rebirth)} × Boosts ${fmtMult(boosts)})`;
	}

	player.GetAttributeChangedSignal("MoneyMult").Connect(refresh);
	player.GetAttributeChangedSignal("MultRebirth").Connect(refresh);
	player.GetAttributeChangedSignal("MoneyTierMult").Connect(refresh);
	player.GetAttributeChangedSignal("InCommunity").Connect(refresh);
	refresh();
}
