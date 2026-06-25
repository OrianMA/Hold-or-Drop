import { Players, TweenService } from "@rbxts/services";

// Gives the "moving cost" label on the HUD multiplier buy button a constant, gentle
// wobble — rotating smoothly between +ANGLE and -ANGLE degrees forever to draw the
// eye. Purely cosmetic, client-only.
//
// One looping tween (RepeatCount -1, Reverses true) on the label's Rotation does the
// whole thing: starting at +ANGLE and easing to -ANGLE with a Sine in/out curve, the
// reverse brings it back, so it oscillates seamlessly without any per-frame work.

const ANGLE = 10;
const TWEEN_INFO = new TweenInfo(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true);

export function init(): void {
	const player = Players.LocalPlayer;

	const label = (player.WaitForChild("PlayerGui") as PlayerGui)
		.WaitForChild("InGameUI")
		.WaitForChild("HUD")
		.WaitForChild("BottomList")
		.WaitForChild("MultiplierBuyButton")
		.WaitForChild("CostMovingtext") as TextLabel;

	label.Rotation = ANGLE;
	TweenService.Create(label, TWEEN_INFO, { Rotation: -ANGLE }).Play();
}
