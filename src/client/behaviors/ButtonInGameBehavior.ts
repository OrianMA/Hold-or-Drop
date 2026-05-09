import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { TweenService, UserInputService } from "@rbxts/services";

// Called once at startup — registers all game-state event listeners
export function init(): void {
	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		CameraController.BringBackPlayerCamera();
		print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
	});
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(mainUI: ScreenGui): void {
	const popup = mainUI.WaitForChild("ButtonInGame") as Frame;
	const releaseButton = popup.WaitForChild("ReleaseButton") as TextButton;
	const baseCashText = popup.WaitForChild("BaseCashText") as TextLabel;

	const sliderParent = popup.WaitForChild("Slider") as Frame;
	const multiplierLabel = sliderParent.WaitForChild("MultiplierLabel") as TextLabel;

	const progressBarParent = sliderParent.WaitForChild("ProgressBar") as CanvasGroup;
	const progressionIndicator = progressBarParent.WaitForChild("ProgressionIndicator") as Frame;

	multiplierLabel.Text = "1x";
	progressionIndicator.Position = new UDim2(0, 0, 0.5, 0);

	Events.BaseCashEvent.OnClientEvent.Connect((baseCash: number) => {
		baseCashText.Text = `$${baseCash}`;
	});

	const BASE_MULTIPLIER_TEXT_SIZE = multiplierLabel.TextSize;
	const SIZE_GROWTH_PER_UPDATE = 3;
	const elasticTweenInfo = new TweenInfo(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out);
	let multiplierTextSize = BASE_MULTIPLIER_TEXT_SIZE;

	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		multiplierLabel.Text = `${multiplier}x`;
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE;
		TweenService.Create(multiplierLabel, elasticTweenInfo, {
			TextSize: multiplierTextSize,
		}).Play();
	});

	const fillTweenInfo = new TweenInfo(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);

	Events.ProgressUpdateEvent.OnClientEvent.Connect((progress: number) => {
		TweenService.Create(progressionIndicator, fillTweenInfo, {
			Position: new UDim2(progress, 0, 0.5, 0),
		}).Play();
	});

	let released = false;

	const fireRelease = () => {
		if (released) return;
		released = true;
		releaseButton.Active = false;
		spaceConn.Disconnect();
		Events.ReleaseButtonEvent.FireServer();
	};

	releaseButton.Activated.Connect(fireRelease);

	const spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireRelease();
	});

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		print("Button exploded!");
		// Disable input after the 0.2s grace period if the player hasn't already released
		task.delay(0.2, () => {
			if (!released) {
				releaseButton.Active = false;
				spaceConn.Disconnect();
			}
		});
	});
}
