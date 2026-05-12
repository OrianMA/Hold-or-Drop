import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { Lighting, RunService, TweenService, UserInputService, Workspace } from "@rbxts/services";

// UI refs — assigned on first setup(), never change after
let releaseButton: TextButton | undefined;
let baseCashText: TextLabel | undefined;
let multiplierLabel: TextLabel | undefined;
let progressionIndicator: Frame | undefined;
let vignetteCanvas: CanvasGroup | undefined;
let buttonOriginalSize: UDim2 | undefined;
let multiplierTextOriginalSize: number | undefined;
let multiplierTextOriginalColor: Color3 | undefined;

// Lighting effects — created once in init()
let colorCorrection: ColorCorrectionEffect | undefined;
let bloomEffect: BloomEffect | undefined;

// Per-game state
let isGameActive = false;
let released = false;
let multiplierTextSize = 0;
let baseMultiplierTextSize = 0;
let shakeAmplitude = 0;
let spaceConn: RBXScriptConnection | undefined;
let activatedConn: RBXScriptConnection | undefined;

const SIZE_GROWTH_PER_UPDATE = 4;
const MAX_MULTIPLIER_SIZE_INCREASE = 80;
const MAX_SHAKE_AMPLITUDE = 0.08;
const MAX_BLOOM_INTENSITY = 1.5;
const MIN_VIGNETTE_TRANSPARENCY = 0.2;

const UpgradeMultiplayerTI = new TweenInfo(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const ReleaseButtonDesapearTI = new TweenInfo(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FillProgressBarTI = new TweenInfo(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);
const PostProcessTI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ResetPostProcessTI = new TweenInfo(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

function createVignetteEdge(
	parent: Instance,
	rotation: number,
	anchorPoint: Vector2,
	position: UDim2,
	size: UDim2,
): Frame {
	const frame = new Instance("Frame");
	frame.BackgroundColor3 = new Color3(0, 0, 0);
	frame.BorderSizePixel = 0;
	frame.AnchorPoint = anchorPoint;
	frame.Position = position;
	frame.Size = size;
	frame.ZIndex = 10;
	frame.Parent = parent;

	const gradient = new Instance("UIGradient");
	gradient.Transparency = new NumberSequence([
		new NumberSequenceKeypoint(0, 0),
		new NumberSequenceKeypoint(1, 1),
	]);
	gradient.Rotation = rotation;
	gradient.Parent = frame;

	return frame;
}

function buildVignette(mainUI: ScreenGui): CanvasGroup {
	const canvas = new Instance("CanvasGroup");
	canvas.Name = "VignetteCanvas";
	canvas.Size = new UDim2(1, 0, 1, 0);
	canvas.Position = new UDim2(0, 0, 0, 0);
	canvas.BackgroundTransparency = 1;
	canvas.GroupTransparency = 1;
	canvas.ZIndex = 10;
	canvas.Parent = mainUI;

	// Four gradient edges: top, bottom, left, right
	// Rotation controls which side is opaque (0 = opaque at start of gradient direction)
	createVignetteEdge(canvas, 90, new Vector2(0.5, 0), new UDim2(0.5, 0, 0, 0), new UDim2(1, 0, 0.45, 0));
	createVignetteEdge(canvas, 270, new Vector2(0.5, 1), new UDim2(0.5, 0, 1, 0), new UDim2(1, 0, 0.45, 0));
	createVignetteEdge(canvas, 0, new Vector2(0, 0.5), new UDim2(0, 0, 0.5, 0), new UDim2(0.45, 0, 1, 0));
	createVignetteEdge(canvas, 180, new Vector2(1, 0.5), new UDim2(1, 0, 0.5, 0), new UDim2(0.45, 0, 1, 0));

	return canvas;
}

function resetPostProcess(instant = false): void {
	const ti = instant ? new TweenInfo(0) : ResetPostProcessTI;
	if (vignetteCanvas) {
		TweenService.Create(vignetteCanvas, ti, { GroupTransparency: 1 }).Play();
	}
	if (colorCorrection) {
		TweenService.Create(colorCorrection, ti, {
			TintColor: new Color3(1, 1, 1),
			Saturation: 0,
		}).Play();
	}
	if (bloomEffect) {
		TweenService.Create(bloomEffect, ti, { Intensity: 0 }).Play();
	}
	shakeAmplitude = 0;
}

function endInput(): void {
	isGameActive = false;
	released = true;
	spaceConn?.Disconnect();
	spaceConn = undefined;
	resetPostProcess();
	if (releaseButton) {
		releaseButton.Active = false;
		let tween = TweenService.Create(releaseButton, ReleaseButtonDesapearTI, { Size: new UDim2(0, 0, 0, 0) });
		tween.Play();
		tween.Completed.Wait();
		releaseButton.Visible = false;
	}
}

// Called once at startup — all event listeners live here, gated by isGameActive
export function init(): void {
	colorCorrection = new Instance("ColorCorrectionEffect");
	colorCorrection.Name = "HoldOrDropCC";
	colorCorrection.Parent = Lighting;

	bloomEffect = new Instance("BloomEffect");
	bloomEffect.Name = "HoldOrDropBloom";
	bloomEffect.Intensity = 0;
	bloomEffect.Size = 24;
	bloomEffect.Threshold = 0.95;
	bloomEffect.Parent = Lighting;

	// Shake loop — runs after the camera updates each frame, amplitude controlled per-game
	RunService.BindToRenderStep("HoldOrDropShake", Enum.RenderPriority.Camera.Value + 1, () => {
		if (shakeAmplitude <= 0) return;
		const camera = Workspace.CurrentCamera;
		if (!camera) return;
		const offset = CFrame.Angles(
			(math.random() - 0.5) * shakeAmplitude,
			(math.random() - 0.5) * shakeAmplitude,
			(math.random() - 0.5) * shakeAmplitude * 0.3,
		);
		camera.CFrame = camera.CFrame.mul(offset);
	});

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

		const factor = math.clamp(
			(multiplierTextSize - (multiplierTextOriginalSize ?? 0)) / MAX_MULTIPLIER_SIZE_INCREASE,
			0,
			1,
		);

		const targetTextColor = (multiplierTextOriginalColor ?? new Color3(1, 1, 1)).Lerp(new Color3(1, 0, 0), factor);
		TweenService.Create(multiplierLabel, UpgradeMultiplayerTI, {
			TextSize: multiplierTextSize,
			TextColor3: targetTextColor,
		}).Play();

		if (vignetteCanvas) {
			TweenService.Create(vignetteCanvas, PostProcessTI, {
				GroupTransparency: 1 - factor * (1 - MIN_VIGNETTE_TRANSPARENCY),
			}).Play();
		}

		if (colorCorrection) {
			TweenService.Create(colorCorrection, PostProcessTI, {
				TintColor: new Color3(1, 1 - factor * 0.5, 1 - factor * 0.5),
				Saturation: -factor * 0.4,
			}).Play();
		}

		if (bloomEffect) {
			TweenService.Create(bloomEffect, PostProcessTI, {
				Intensity: factor * MAX_BLOOM_INTENSITY,
			}).Play();
		}

		shakeAmplitude = factor * MAX_SHAKE_AMPLITUDE;
	});

	Events.ProgressUpdateEvent.OnClientEvent.Connect((progress: number) => {
		if (!isGameActive || !progressionIndicator) return;
		TweenService.Create(progressionIndicator, FillProgressBarTI, {
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

	// Save original sizes/colors on first run so we can restore each game
	if (!buttonOriginalSize) buttonOriginalSize = releaseButton.Size;
	if (!multiplierTextOriginalSize) multiplierTextOriginalSize = multiplierLabel.TextSize;
	if (!multiplierTextOriginalColor) multiplierTextOriginalColor = multiplierLabel.TextColor3;
	if (!vignetteCanvas) vignetteCanvas = buildVignette(mainUI);

	// Reset per-game state
	isGameActive = true;
	released = false;
	multiplierLabel.TextSize = multiplierTextOriginalSize;
	multiplierLabel.TextColor3 = multiplierTextOriginalColor;
	multiplierTextSize = multiplierTextOriginalSize;
	resetPostProcess(true);

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
