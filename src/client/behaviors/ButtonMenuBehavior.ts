import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { InGameUIController } from "client/ui/InGameUIController";
import { Players } from "@rbxts/services";

// onGameStart is called with inGameUI once the player clicks StartButton
export function init(onGameStart: (inGameUI: ScreenGui) => void): void {
	let startConn: RBXScriptConnection | undefined;
	let quitConn: RBXScriptConnection | undefined;

	// UI is guaranteed to exist after the server triggered this event
	const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const inGameUI = playerGui.WaitForChild("InGameUI") as ScreenGui;
	const buttonMenu = inGameUI.WaitForChild("ButtonMenu") as Frame;

	const startButton = buttonMenu.WaitForChild("StartButton") as TextButton;
	const quitButton = buttonMenu.WaitForChild("QuitButton") as TextButton;

	Events.ButtonTriggerEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
		CameraController.SetCinematic();
		CameraController.AnimateTo(cameraPosPart.CFrame);

		// Menu is open → hide the persistent HUD behind it.
		InGameUIController.disable();

		DisconnectEvents();

		startConn = startButton.Activated.Connect(() => {
			DisconnectEvents();
			Events.StartButtonClickedEvent.FireServer();
			// Keep the HUD hidden during gameplay — it comes back when the
			// EndGameButton (ButtonFinishGame) opens.
			onGameStart(inGameUI);
		});

		quitConn = quitButton.Activated.Connect(() => {
			DisconnectEvents();
			Events.QuitButtonClickedEvent.FireServer();
			CameraController.BringBackPlayerCamera();
			// Cancelled the menu → restore the HUD.
			InGameUIController.enable();
		});
	});

	function DisconnectEvents(): void {
		startConn?.Disconnect();
		quitConn?.Disconnect();
	}
}
