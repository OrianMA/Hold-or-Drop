import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { runEndGameAnimation } from "client/ui/EndGameAnimation";

// Entry point for the ButtonFinishGame UI state on the client.
// Server fires EndGameStartEvent after the popup has been shown — we resolve
// the frame and hand off to the animation orchestrator. When the animation
// completes we tell the server to hide the popup (single source of truth).
export function init(): void {
	Events.EndGameStartEvent.OnClientEvent.Connect(
		(baseCash: number, multiplier: number, lossMultiplier: number, multRebirth: number) => {
			const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
			const mainUI = playerGui.WaitForChild("MainUI") as ScreenGui;
			const frame = mainUI.WaitForChild("ButtonFinishGame") as Frame;

			task.spawn(() => {
				runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, multRebirth, () => {
					Events.EndGameFinishedEvent.FireServer();
				});
			});
		},
	);
}
