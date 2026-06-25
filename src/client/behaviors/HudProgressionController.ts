import { Players } from "@rbxts/services";
import { rebirthCost } from "shared/ShopConfig";
import { FormatNumber } from "shared/NumberFormat";
import { MoneyDisplay } from "../ui/MoneyDisplay";

// Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar).
// It shows the same thing as the Rebirth menu bar (RebirthMenuController): progress
// toward the next rebirth, Money / rebirthCost(Rebirths).
//
// Instead of running its own tween, the bar MIRRORS the money HUD's displayed value
// (MoneyDisplay.subscribe) — so the fill and the "money / cost" number count up in
// perfect lockstep with the money counter, at the same speed, including the cosmetic
// payout count-up. The cost only changes on rebirth.
//
// The fill also swaps its gradient: the "progress" gradient while filling, and the
// "finish" gradient once the bar is full (money >= cost). Both gradients are authored
// inside CurrentProgressionFrame in Studio.

const player = Players.LocalPlayer;
const PROGRESS_GRADIENT = "UIGradientProgress";
const FINISH_GRADIENT = "UiGradientFinish";

function getRebirths(): number {
	return (player.GetAttribute("Rebirths") as number | undefined) ?? 0;
}

export function init(): void {
	const progressionBar = (player.WaitForChild("PlayerGui") as PlayerGui)
		.WaitForChild("InGameUI")
		.WaitForChild("HUD")
		.WaitForChild("BottomList")
		.WaitForChild("ProgressionBar");

	const fill = progressionBar.WaitForChild("CurrentProgressionFrame") as Frame;
	const moneyNeededText = progressionBar.WaitForChild("BackgroundFrame").WaitForChild("MoneyNeededText") as TextLabel;

	const progressGradient = fill.FindFirstChild(PROGRESS_GRADIENT) as UIGradient | undefined;
	const finishGradient = fill.FindFirstChild(FINISH_GRADIENT) as UIGradient | undefined;

	// The cost only changes on rebirth; cached so the per-step render stays cheap.
	let cost = rebirthCost(getRebirths());
	let lastMoney = 0;

	function render(money: number): void {
		lastMoney = money;
		const progress = math.clamp(money / cost, 0, 1);
		fill.Size = new UDim2(progress, 0, 1, 0);
		moneyNeededText.Text = `${FormatNumber(math.floor(money))} / ${FormatNumber(cost)}`;

		// Full bar → "finish" gradient, otherwise the "progress" gradient.
		const full = progress >= 1;
		if (progressGradient) progressGradient.Enabled = !full;
		if (finishGradient) finishGradient.Enabled = full;
	}

	// Mirror the animated money value so the bar counts up in sync with the HUD money.
	MoneyDisplay.subscribe(render);

	// On rebirth the cost jumps; re-render with the current displayed money.
	player.GetAttributeChangedSignal("Rebirths").Connect(() => {
		cost = rebirthCost(getRebirths());
		render(lastMoney);
	});
}
