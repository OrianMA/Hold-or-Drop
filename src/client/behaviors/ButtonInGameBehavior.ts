import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { TweenService, UserInputService } from "@rbxts/services";

// Called once at startup — registers all game-state event listeners
export function init(): void {
	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		print("Button exploded!");
	});

	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		CameraController.BringBackPlayerCamera();
		print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
	});
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(mainUI: ScreenGui): void {
	const buttonInGame = mainUI.WaitForChild("ButtonInGame") as Frame;
	const releaseButton = buttonInGame.WaitForChild("ReleaseButton") as TextButton;
	const multiplierLabel = buttonInGame.WaitForChild("MultiplierLabel") as TextLabel;
	const progressBar = buttonInGame.WaitForChild("ProgressBar") as CanvasGroup;
	const fill = progressBar.WaitForChild("Fill") as Frame;

	multiplierLabel.Text = "1x";
	fill.Size = new UDim2(0, 0, fill.Size.Y.Scale, 0);

	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		multiplierLabel.Text = `${multiplier}x`;
	});

	const fillTweenInfo = new TweenInfo(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);

	Events.ProgressUpdateEvent.OnClientEvent.Connect((progress: number) => {
		TweenService.Create(fill, fillTweenInfo, { Size: new UDim2(progress, 0, fill.Size.Y.Scale, 0) }).Play();
	});

	let released = false;

	const fireRelease = () => {
		if (released) return;
		released = true;
		spaceConn.Disconnect();
		Events.ReleaseButtonEvent.FireServer();
	};

	releaseButton.Activated.Connect(fireRelease);

	const spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireRelease();
	});
}
