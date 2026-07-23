import { Events } from "shared/Event";
import { InGameUIController } from "client/ui/InGameUIController";
import { FloatingReward } from "client/ui/FloatingReward";
import { MusicController } from "client/audio/MusicController";

// ── Losing-explosion consolation ────────────────────────────────────────────────
//
// On a losing explosion there is NO ButtonFinishGame popup (see §6.3). Instead the
// player gets a flat consolation (baseCash / 3, computed server-side) shown as a
// single "+amount" text that jumps then flies into the money HUD (FloatingReward,
// "fly" ending). The text banks the cash on arrival and fires EndGameFinishedEvent
// so the server credits the real Money via the shared pendingEarned path.

export function init(): void {
	Events.LossRewardEvent.OnClientEvent.Connect((amount: number) => {
		// The HUD was hidden during gameplay; bring it back so the money counter is
		// visible for the text to fly into (GameResultEvent already stopped the held
		// pose and returned the camera).
		InGameUIController.enable();
		// Run fully over → ease the BGM back in once the text has landed.
		FloatingReward.show(amount, "fly", () => MusicController.resumeBgm());
	});
}
