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
			InGameUIController.enable();
			ButtonAnimations.restoreDefault();

			const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
			const inGameUI = playerGui.WaitForChild("InGameUI") as ScreenGui;
			const frame = inGameUI.WaitForChild("ButtonFinishGame") as Frame;

			task.spawn(() => {
				runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, () => {
					Events.EndGameFinishedEvent.FireServer();
					MusicController.resumeBgm();
				});
			});
		},
	);
}
