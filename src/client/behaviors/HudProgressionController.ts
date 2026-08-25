import { Players, TweenService } from "@rbxts/services";
import { rebirthCost } from "shared/ShopConfig";
import { FormatNumber } from "shared/NumberFormat";
import { MoneyDisplay } from "../ui/MoneyDisplay";
import { openRebirthMenu } from "./RebirthMenuBehavior";

// Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar)
// and the rebirth button's percentage label (HUD/ButtonsFrame/RebirthFrame/PourcetageText).
// They show the same thing as the Rebirth menu bar (RebirthMenuController): progress
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
//
// Two display states:
//  - filling  → RebirthFrame (RebirthImage + RebirthLevelText "Rebirth N") + BackgroundFrame (money/cost)
//  - ready    → those hide, LevelUpText ("Click to rebirth") shows with a golden shimmer
//               and RebirthButton (inside the now full-width fill) opens the rebirth popup.

const player = Players.LocalPlayer;
const PROGRESS_GRADIENT = "UIGradientProgress";
const FINISH_GRADIENT = "UiGradientFinish";

// Smallest X-scale the fill is allowed to render at. Below this the sliver is too thin
// to read (rounded corners/stroke collapse), so the fill is hidden entirely until
// progress reaches it. At/above it, the fill never renders thinner than this.
const MIN_VISIBLE_PROGRESS = 0.013;

// Golden shimmer on LevelUpText: the gradient sweeps left → right on a loop while a
// slow size pulse makes the label breathe.
const SHIMMER_INFO = new TweenInfo(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1);
const PULSE_INFO = new TweenInfo(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true);
const PULSE_SCALE = 1.08;

function getRebirths(): number {
	return (player.GetAttribute("Rebirths") as number | undefined) ?? 0;
}

export function init(): void {
	const hud = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI").WaitForChild("HUD");
	const progressionBar = hud.WaitForChild("BottomList").WaitForChild("ProgressionBar");
	const percentText = hud
		.WaitForChild("ButtonsFrame")
		.WaitForChild("RebirthFrame")
		.WaitForChild("PourcetageText") as TextLabel;

	const fill = progressionBar.WaitForChild("CurrentProgressionFrame") as Frame;
	const backgroundFrame = progressionBar.WaitForChild("BackgroundFrame") as Frame;
	const moneyNeededText = backgroundFrame.WaitForChild("MoneyNeededText") as TextLabel;
	const rebirthFrame = progressionBar.WaitForChild("RebirthFrame") as Frame;
	const rebirthLevelText = rebirthFrame.WaitForChild("RebirthLevelText") as TextLabel;
	const levelUpText = progressionBar.WaitForChild("LevelUpText") as TextLabel;
	const rebirthButton = fill.WaitForChild("RebirthButton") as GuiButton;

	const progressGradient = fill.FindFirstChild(PROGRESS_GRADIENT) as UIGradient | undefined;
	const finishGradient = fill.FindFirstChild(FINISH_GRADIENT) as UIGradient | undefined;
	const goldGradient = levelUpText.FindFirstChild("GoldGradient") as UIGradient | undefined;

	const baseLevelUpSize = levelUpText.Size;
	const pulsedLevelUpSize = new UDim2(
		baseLevelUpSize.X.Scale * PULSE_SCALE,
		baseLevelUpSize.X.Offset * PULSE_SCALE,
		baseLevelUpSize.Y.Scale * PULSE_SCALE,
		baseLevelUpSize.Y.Offset * PULSE_SCALE,
	);
	const shimmerTween = goldGradient
		? TweenService.Create(goldGradient, SHIMMER_INFO, { Offset: new Vector2(1, 0) })
		: undefined;
	const pulseTween = TweenService.Create(levelUpText, PULSE_INFO, { Size: pulsedLevelUpSize });

	// The cost only changes on rebirth; cached so the per-step render stays cheap.
	let cost = rebirthCost(getRebirths());
	let lastMoney = 0;
	let ready = false;

	// Swaps between the "filling" widgets and the "ready to rebirth" call to action.
	function setReady(value: boolean): void {
		if (ready === value) return;
		ready = value;

		rebirthFrame.Visible = !value;
		backgroundFrame.Visible = !value;
		levelUpText.Visible = value;
		rebirthButton.Visible = value;

		if (value) {
			if (goldGradient) goldGradient.Offset = new Vector2(-1, 0);
			shimmerTween?.Play();
			pulseTween.Play();
		} else {
			shimmerTween?.Cancel();
			pulseTween.Cancel();
			levelUpText.Size = baseLevelUpSize;
		}
	}

	function render(money: number): void {
		lastMoney = money;
		const progress = math.clamp(money / cost, 0, 1);
		moneyNeededText.Text = `${FormatNumber(math.floor(money))} / ${FormatNumber(cost)}`;

		// Whole percent, floored so it only reads "100%" once the rebirth is actually affordable.
		percentText.Text = `${math.floor(progress * 100)}%`;

		const full = progress >= 1;
		setReady(full);

		// Below the minimum displayable percentage, hide the fill rather than show an
		// unreadable sliver. At/above it, show the fill clamped to that minimum width.
		if (progress < MIN_VISIBLE_PROGRESS) {
			fill.Visible = false;
			return;
		}
		fill.Visible = true;
		fill.Size = new UDim2(math.max(progress, MIN_VISIBLE_PROGRESS), 0, 1, 0);

		// Full bar → "finish" gradient, otherwise the "progress" gradient.
		if (progressGradient) progressGradient.Enabled = !full;
		if (finishGradient) finishGradient.Enabled = full;
	}

	function renderRebirthLevel(): void {
		rebirthLevelText.Text = `Rebirth ${getRebirths()}`;
	}

	rebirthButton.Activated.Connect(() => openRebirthMenu());

	// Mirror the animated money value so the bar counts up in sync with the HUD money.
	MoneyDisplay.subscribe(render);

	// On rebirth the cost jumps; re-render with the current displayed money.
	player.GetAttributeChangedSignal("Rebirths").Connect(() => {
		cost = rebirthCost(getRebirths());
		renderRebirthLevel();
		render(lastMoney);
	});

	renderRebirthLevel();
	// Force the initial state onto the widgets (setReady early-returns when unchanged).
	ready = true;
	setReady(false);
}
