import { Players, TweenService } from "@rbxts/services";
import { rebirthCost } from "shared/ShopConfig";
import { FormatNumber } from "shared/NumberFormat";

// Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar).
// It shows the same thing as the Rebirth menu bar (RebirthMenuController): progress
// toward the next rebirth, Money / rebirthCost(Rebirths). The difference is purely
// visual — here the fill and the number count up smoothly when the player earns
// money, instead of snapping.
//
// A single NumberValue proxy is tweened toward the live Money value (same pattern as
// MoneyDisplay). On every Changed step we mirror the proxy into both the fill width
// (X-scale = money/cost) and the "money / cost" label, so the two stay perfectly in
// sync through the tween. Mid-flight earnings cancel and restart from the current
// visual value. A rebirth (cost jumps, money resets) snaps instead of tweening.

const player = Players.LocalPlayer;

// Quad-Out count-up — matches the punchy feel of the money HUD.
const TWEEN_INFO = new TweenInfo(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

function getMoney(): number {
	return (player.GetAttribute("Money") as number | undefined) ?? 0;
}

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

	// The cost only changes on rebirth; cached so the per-step render stays cheap.
	let cost = rebirthCost(getRebirths());
	let displayValue = 0;
	let initialized = false;
	let activeTween: Tween | undefined;

	const proxy = new Instance("NumberValue");

	function render(value: number): void {
		const progress = math.clamp(value / cost, 0, 1);
		fill.Size = new UDim2(progress, 0, 1, 0);
		moneyNeededText.Text = `${FormatNumber(math.floor(value))} / ${FormatNumber(cost)}`;
	}

	proxy.Changed.Connect((v) => {
		displayValue = v;
		render(v);
	});

	// Cancel any in-flight tween and head from where we *visually* are toward the
	// target. Snaps when already there.
	function tweenTo(target: number): void {
		if (activeTween !== undefined) {
			activeTween.Cancel();
			activeTween = undefined;
		}

		if (math.floor(displayValue) === math.floor(target)) {
			proxy.Value = target;
			return;
		}

		proxy.Value = displayValue;
		const tween = TweenService.Create(proxy, TWEEN_INFO, { Value: target });
		activeTween = tween;
		const completed = tween.Completed.Connect(() => {
			completed.Disconnect();
			if (activeTween === tween) {
				activeTween = undefined;
				proxy.Value = target;
			}
		});
		tween.Play();
	}

	function onMoneyChanged(): void {
		const money = getMoney();

		// First update on join: snap so the bar doesn't sweep up from 0 on every load.
		if (!initialized) {
			initialized = true;
			proxy.Value = money;
			displayValue = money;
			render(money);
			return;
		}

		tweenTo(money);
	}

	// On rebirth the cost jumps and money resets — snap to the new state rather than
	// animating a confusing backwards sweep.
	function onRebirthChanged(): void {
		if (activeTween !== undefined) {
			activeTween.Cancel();
			activeTween = undefined;
		}
		cost = rebirthCost(getRebirths());
		const money = getMoney();
		proxy.Value = money;
		displayValue = money;
		render(money);
	}

	player.GetAttributeChangedSignal("Money").Connect(onMoneyChanged);
	player.GetAttributeChangedSignal("Rebirths").Connect(onRebirthChanged);
	onMoneyChanged();
}
