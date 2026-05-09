import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { TweenService, UserInputService } from "@rbxts/services";

// UI refs — assigned on first setup(), never change after
let releaseButton: TextButton | undefined;
let baseCashText: TextLabel | undefined;
let multiplierLabel: TextLabel | undefined;
let progressionIndicator: Frame | undefined;
let buttonOriginalSize: UDim2 | undefined;

// Per-game state
let isGameActive = false;
let released = false;
let multiplierTextSize = 0;
let spaceConn: RBXScriptConnection | undefined;
let activatedConn: RBXScriptConnection | undefined;

const SIZE_GROWTH_PER_UPDATE = 3;
const elasticTweenInfo = new TweenInfo(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out);
const shrinkTweenInfo = new TweenInfo(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.In);
const fillTweenInfo = new TweenInfo(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);

function endInput(): void {
	isGameActive = false;
	released = true;
	spaceConn?.Disconnect();
	spaceConn = undefined;
	if (releaseButton) {
		releaseButton.Active = false;
		let tween = TweenService.Create(releaseButton, shrinkTweenInfo, { Size: new UDim2(0, 0, 0, 0) });
		tween.Play();
		tween.Completed.Wait();
		releaseButton.Visible = false;
	}
}

// Called once at startup — all event listeners live here, gated by isGameActive
export function init(): void {
	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		CameraController.BringBackPlayerCamera();
		print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
	});

	Events.BaseCashEvent.OnClientEvent.Connect((baseCash: number) => {
		if (!isGameActive || !baseCashText) return;
		baseCashText.Text = `$${baseCash}`;
	});

	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		if (!isGameActive || !multiplierLabel) return;
		multiplierLabel.Text = `${multiplier}x`;
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE;
		TweenService.Create(multiplierLabel, elasticTweenInfo, { TextSize: multiplierTextSize }).Play();
	});

	Events.ProgressUpdateEvent.OnClientEvent.Connect((progress: number) => {
		if (!isGameActive || !progressionIndicator) return;
		TweenService.Create(progressionIndicator, fillTweenInfo, {
			Position: new UDim2(progress, 0, 0.5, 0),
		}).Play();
	});

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		if (!isGameActive) return;
		print("Button exploded!");
		// Grace period: player can still release to cancel the explosion
		task.delay(0.2, () => {
			if (!released) endInput();
		});
	});
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(mainUI: ScreenGui): void {
	const popup = mainUI.WaitForChild("ButtonInGame") as Frame;
	releaseButton = popup.WaitForChild("ReleaseButton") as TextButton;
	baseCashText = popup.WaitForChild("BaseCashText") as TextLabel;
	const sliderParent = popup.WaitForChild("Slider") as Frame;
	multiplierLabel = sliderParent.WaitForChild("MultiplierLabel") as TextLabel;
	const progressBarParent = sliderParent.WaitForChild("ProgressBar") as CanvasGroup;
	progressionIndicator = progressBarParent.WaitForChild("ProgressionIndicator") as Frame;

	// Save original button size on first run so we can restore it each game
	if (!buttonOriginalSize) buttonOriginalSize = releaseButton.Size;

	// Reset per-game state
	isGameActive = true;
	released = false;
	multiplierTextSize = multiplierLabel.TextSize;

	// Restore button to full size and re-enable it
	releaseButton.Size = buttonOriginalSize;
	releaseButton.Active = true;
	releaseButton.Visible = true;
	print(releaseButton.Activated);

	// Reset UI
	multiplierLabel.Text = "1x";
	progressionIndicator.Position = new UDim2(0, 0, 0.5, 0);

	// Clean up any leftover connections from a previous game
	spaceConn?.Disconnect();
	activatedConn?.Disconnect();

	const fireRelease = () => {
		if (!isGameActive || released) return;
		endInput();
		Events.ReleaseButtonEvent.FireServer();
	};

	activatedConn = releaseButton.Activated.Connect(fireRelease);

	spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed || !isGameActive || released) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireRelease();
	});
}
