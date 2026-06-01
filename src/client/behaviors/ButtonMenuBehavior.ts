import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { Players } from "@rbxts/services";

// onGameStart is called with mainUI once the player clicks StartButton
export function init(onGameStart: (mainUI: ScreenGui) => void): void {
	let startConn: RBXScriptConnection | undefined;
	let quitConn: RBXScriptConnection | undefined;

	// UI is guaranteed to exist after the server triggered this event
	const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const mainUI = playerGui.WaitForChild("MainUI") as ScreenGui;
	const buttonMenu = mainUI.WaitForChild("ButtonMenu") as Frame;

	const startButton = buttonMenu.WaitForChild("StartButton") as TextButton;
	const quitButton = buttonMenu.WaitForChild("QuitButton") as TextButton;

	Events.ButtonTriggerEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
		CameraController.SetCinematic();
		CameraController.AnimateTo(cameraPosPart.CFrame);

		DisconnectEvents();

		startConn = startButton.Activated.Connect(() => {
			DisconnectEvents();
			Events.StartButtonClickedEvent.FireServer();
			onGameStart(mainUI);
		});

		quitConn = quitButton.Activated.Connect(() => {
			DisconnectEvents();
			Events.QuitButtonClickedEvent.FireServer();
			CameraController.BringBackPlayerCamera();
		});
	});

	function DisconnectEvents(): void {
		startConn?.Disconnect();
		quitConn?.Disconnect();
	}
}
