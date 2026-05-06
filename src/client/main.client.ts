import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { Players } from "@rbxts/services";

Events.ButtonTriggerEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
	CameraController.SetCinematic();
	CameraController.AnimateTo(cameraPosPart.CFrame);

	const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const mainUI = playerGui.WaitForChild("MainUI") as ScreenGui;
	const buttonMenu = mainUI.WaitForChild("ButtonMenu") as Frame;
	const startButton = buttonMenu.WaitForChild("StartButton") as TextButton;

	startButton.Activated.Connect(() => {
		Events.StartButtonClickedEvent.FireServer();
	});
});
