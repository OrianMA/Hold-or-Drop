import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { Players, UserInputService } from "@rbxts/services";

Events.ButtonTriggerEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
	CameraController.SetCinematic();
	CameraController.AnimateTo(cameraPosPart.CFrame);

	const playerGui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const mainUI = playerGui.WaitForChild("MainUI") as ScreenGui;
	const buttonMenu = mainUI.WaitForChild("ButtonMenu") as Frame;
	const startButton = buttonMenu.WaitForChild("StartButton") as TextButton;

	startButton.Activated.Connect(() => {
		Events.StartButtonClickedEvent.FireServer();
		setupButtonInGame(mainUI);
	});
});

function setupButtonInGame(mainUI: ScreenGui): void {
	const buttonInGame = mainUI.WaitForChild("ButtonInGame") as Frame;
	const releaseButton = buttonInGame.WaitForChild("ReleaseButton") as TextButton;

	let released = false;

	const fireRelease = () => {
		if (released) return;
		released = true;
		spaceConn.Disconnect();
		Events.ReleaseButtonEvent.FireServer();
	};

	// UI button
	releaseButton.Activated.Connect(fireRelease);

	// Spacebar
	const spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireRelease();
	});
}

Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
	// TODO: update multiplier label in ButtonInGame UI
	print(`Multiplier: ${multiplier}x`);
});

Events.RiskUpdateEvent.OnClientEvent.Connect((risk: number) => {
	// risk is 0–1 (display as percentage: risk * 100)
	// TODO: update risk indicator in ButtonInGame UI
	print(`Risk: ${math.round(risk * 100)}%`);
});

Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
	// TODO: screenshake, stress effect, explosion sound/particles
	print("Button exploded!");
});

Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
	CameraController.BringBackPlayerCamera();
	// TODO: show result popup (cash earned, whether it exploded)
	print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
});
