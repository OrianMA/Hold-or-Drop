import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { cancelActiveRun, runEndGameAnimation } from "client/ui/EndGameAnimation";
import { InGameUIController } from "client/ui/InGameUIController";
import { FloatingReward } from "client/ui/FloatingReward";
import { MusicController } from "client/audio/MusicController";
import { ButtonAnimations } from "client/behaviors/ButtonAnimations";

// Entry point for the ButtonFinishGame UI state on the client.
// Server fires EndGameStartEvent after the popup has been shown — we resolve
// the frame and hand off to the animation orchestrator. When the animation
// completes we tell the server to hide the popup (single source of truth).
export function init(): void {
	Events.EndGameStartEvent.OnClientEvent.Connect(
		(baseCash: number, multiplier: number, lossMultiplier: number, claimBonus: number) => {
			// The finish popup is opening — bring back the persistent HUD that the
			// ButtonMenu hid, so the payout animation can fly cash into it.
			InGameUIController.enable();
			// Payout screen is up → return the rig to the default Roblox animations
			// (ends a still-playing release clip).
			ButtonAnimations.restoreDefault();

			const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
			const inGameUI = playerGui.WaitForChild("InGameUI") as ScreenGui;
			const frame = inGameUI.WaitForChild("ButtonFinishGame") as Frame;

			task.spawn(() => {
				runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, claimBonus, () => {
					Events.EndGameFinishedEvent.FireServer();
					// Run fully over → ease the BGM back in (also covered by respawn on death).
					MusicController.resumeBgm();
				});
			});
		},
	);

	// Another popup opened while the payout was pending — typically the player
	// re-triggered the button or the rocket during the release delay, or mid-animation.
	// The finish screen is dropped entirely (no popup, no HUD restore, no BGM resume):
	// the screen they just opened keeps the focus, and the gain leaves as one floating
	// text that fades on the spot. `earned` is the server's total; a running animation
	// overrides it with what its chunks have not already banked.
	Events.EndGamePayoutFlushEvent.OnClientEvent.Connect((earned: number) => {
		const remaining = cancelActiveRun();

		// Nothing was animating and a reward text is already on screen (losing-explosion
		// consolation still in flight) — that text is the gain, don't stack a second one.
		if (remaining === undefined && FloatingReward.isActive()) return;

		const amount = remaining ?? earned;
		if (amount <= 0) {
			// Everything already landed in the HUD — just close the server-side pending.
			Events.EndGameFinishedEvent.FireServer();
			return;
		}

		FloatingReward.show(amount, "fade");
	});
}
