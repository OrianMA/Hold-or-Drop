import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { runEndGameAnimation } from "client/ui/EndGameAnimation";
import { InGameUIController } from "client/ui/InGameUIController";
import { MusicController } from "client/audio/MusicController";
import { ButtonAnimations } from "client/behaviors/ButtonAnimations";

// Entry point for the ButtonFinishGame UI state on the client.
// Server fires EndGameStartEvent after the popup has been shown — we resolve
// the frame and hand off to the animation orchestrator. When the animation
// completes we tell the server to hide the popup (single source of truth).
export function init(): void {
	Events.EndGameStartEvent.OnClientEvent.Connect(
		(baseCash: number, multiplier: number, lossMultiplier: number) => {
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
				runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, () => {
					Events.EndGameFinishedEvent.FireServer();
					// Run fully over → ease the BGM back in (also covered by respawn on death).
					MusicController.resumeBgm();
				});
			});
		},
	);
}
