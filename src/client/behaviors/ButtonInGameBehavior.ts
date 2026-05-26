import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import {
	ContentProvider,
	GuiService,
	Lighting,
	Players,
	RunService,
	SoundService,
	TweenService,
	UserInputService,
	Workspace,
} from "@rbxts/services";

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
let baseFov = 70;
let spaceConn: RBXScriptConnection | undefined;
let activatedConn: RBXScriptConnection | undefined;
let parryKnockbackCamConn: RBXScriptConnection | undefined;
let parryAnimTrack: AnimationTrack | undefined;

// Son bouton — joué via playSound() (non-3D, personnel)
const SOUND_BUTTON_EXPLODE_ID = "rbxassetid://133384716023284";
const SOUND_PARRY_ID = "rbxassetid://119580857539801";

// Template persistant en SoundService : le client garde l'asset en mémoire dès le démarrage.
// Cloner ce template au moment du parry élimine le fetch CDN et le délai de buffering.
const parrySoundTemplate = (() => {
	const sound = new Instance("Sound");
	sound.Name = "ParrySoundTemplate";
	sound.SoundId = SOUND_PARRY_ID;
	sound.Volume = 1;
	sound.Parent = SoundService;
	return sound;
})();

// Animation perfect parry — remplace l'ID par celui récupéré depuis la toolbox
const ANIM_PARRY_ID = "rbxassetid://6481315203";

function playSound(id: string, volume = 1, pitch = 1): void {
	const sound = new Instance("Sound");
	sound.SoundId = id;
	sound.Volume = volume;
	sound.PlaybackSpeed = pitch;
	sound.Parent = SoundService;
	sound.Play();
	sound.Ended.Connect(() => sound.Destroy());
}

const SIZE_GROWTH_PER_UPDATE = 4;
const MAX_MULTIPLIER_SIZE_INCREASE = 80;
const MAX_SHAKE_AMPLITUDE = 0.08;
const MAX_BLOOM_INTENSITY = 1.5;
const MIN_VIGNETTE_TRANSPARENCY = 0.2;
const MIN_FOV = 58;

const UpgradeMultiplayerTI = new TweenInfo(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const ReleaseButtonDesapearTI = new TweenInfo(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FillProgressBarTI = new TweenInfo(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);
const PostProcessTI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ResetPostProcessTI = new TweenInfo(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ZoomResetTI = new TweenInfo(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ExplodeFovPunchTI = new TweenInfo(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const EXPLODE_FOV_OVERSHOOT = 18;

const PerfectParrytime = 1.6;

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
	gradient.Transparency = new NumberSequence([new NumberSequenceKeypoint(0, 0), new NumberSequenceKeypoint(1, 1)]);
	gradient.Rotation = rotation;
	gradient.Parent = frame;

	return frame;
}

function buildVignette(mainUI: ScreenGui): CanvasGroup {
	const [topLeft] = GuiService.GetGuiInset();
	const insetY = topLeft.Y;

	const canvas = new Instance("CanvasGroup");
	canvas.Name = "VignetteCanvas";
	canvas.Size = new UDim2(1, 0, 1, insetY);
	canvas.Position = new UDim2(0, 0, 0, -insetY);
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

function resetPostProcess(instant = false, explode = false): void {
	const ti = instant || explode ? new TweenInfo(0) : ResetPostProcessTI;
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
	const camera = Workspace.CurrentCamera;
	if (camera) {
		if (explode) {
			TweenService.Create(camera, ExplodeFovPunchTI, { FieldOfView: baseFov + EXPLODE_FOV_OVERSHOOT }).Play();
		} else {
			const fovTi = instant ? new TweenInfo(0) : ZoomResetTI;
			TweenService.Create(camera, fovTi, { FieldOfView: baseFov }).Play();
		}
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
		const tween = TweenService.Create(releaseButton, ReleaseButtonDesapearTI, { Size: new UDim2(0, 0, 0, 0) });
		tween.Play();
		tween.Completed.Wait();
		releaseButton.Visible = false;
	}
}

function startParryWindow(): void {
	isGameActive = false;
	resetPostProcess(false, true); // FOV punch + post-process instantané

	spaceConn?.Disconnect();
	spaceConn = undefined;
	activatedConn?.Disconnect();
	activatedConn = undefined;

	if (!releaseButton) {
		released = true;
		return;
	}

	// Le bouton disparaît pendant la fenêtre de parry
	releaseButton.Active = true;
	const tween = TweenService.Create(releaseButton, ReleaseButtonDesapearTI, { Size: new UDim2(0, 0, 0, 0) });
	tween.Play();

	const fireParry = () => {
		if (released) return;
		released = true;
		spaceConn?.Disconnect();
		spaceConn = undefined;
		activatedConn?.Disconnect();
		activatedConn = undefined;
		print("perfect parry");
		Events.PerfectParryEvent.FireServer();
	};

	spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireParry();
	});
	activatedConn = releaseButton.Activated.Connect(fireParry);

	// Fin de la fenêtre de parry
	task.delay(PerfectParrytime, () => {
		spaceConn?.Disconnect();
		spaceConn = undefined;
		activatedConn?.Disconnect();
		activatedConn = undefined;
		released = true;
		releaseButton!.Active = false;
		releaseButton!.Visible = false;
	});
}

// Called once at startup — all event listeners live here, gated by isGameActive
export function init(): void {
	// Préchargement du son bouton (non-template : joué via playSound à la demande)
	task.spawn(() => {
		const s = new Instance("Sound");
		s.SoundId = SOUND_BUTTON_EXPLODE_ID;
		s.Parent = SoundService;
		ContentProvider.PreloadAsync([s]);
		s.Destroy();
	});

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

	Events.PlayerKilledEvent.OnClientEvent.Connect(() => {
		// Son joué côté serveur (3D, entendu par tous)
		CameraController.BringBackPlayerCamera(0);
	});

	Events.PerfectParryEffectEvent.OnClientEvent.Connect(() => {
		// Son d'explosion joué côté serveur (3D, entendu par tous)
		// Son d'épée : clone du template — asset déjà en mémoire, aucun délai de buffering
		const parrySound = parrySoundTemplate.Clone();
		parrySound.Parent = SoundService;
		parrySound.Play();
		parrySound.Ended.Connect(() => parrySound.Destroy());

		const character = Players.LocalPlayer.Character;
		const hrp = character?.FindFirstChild("HumanoidRootPart") as BasePart | undefined;

		// Caméra cinématique : au-dessus et derrière le joueur pour voir la projection
		CameraController.SetCinematic();
		const camera = Workspace.CurrentCamera;
		if (camera) camera.FieldOfView = baseFov; // reset FOV instantanément (évite le zoom glitch)

		if (hrp) {
			// Au moment du parry, le joueur faisait face au bouton → LookVector pointe vers lui
			// On positionne la caméra dans cette direction pour voir le joueur s'envoler
			const behindDir = hrp.CFrame.LookVector;
			const CAM_BEHIND = 12;
			const CAM_HEIGHT = 8;

			parryKnockbackCamConn?.Disconnect();
			parryKnockbackCamConn = RunService.RenderStepped.Connect(() => {
				const cam = Workspace.CurrentCamera;
				if (!cam) return;
				const camPos = hrp.Position.add(behindDir.mul(CAM_BEHIND)).add(new Vector3(0, CAM_HEIGHT, 0));
				cam.CFrame = new CFrame(camPos, hrp.Position.add(new Vector3(0, 1, 0)));
			});
		}

		if (!hrp) return;

		const attachment = new Instance("Attachment");
		attachment.Position = Vector3.zero;
		attachment.Parent = hrp;

		const emitter = new Instance("ParticleEmitter");
		emitter.Color = new ColorSequence([
			new ColorSequenceKeypoint(0, new Color3(1, 1, 1)),
			new ColorSequenceKeypoint(0.4, new Color3(1, 0.9, 0.2)),
			new ColorSequenceKeypoint(1, new Color3(1, 1, 0.6)),
		]);
		emitter.Size = new NumberSequence([
			new NumberSequenceKeypoint(0, 0.5),
			new NumberSequenceKeypoint(0.3, 0.3),
			new NumberSequenceKeypoint(1, 0),
		]);
		emitter.Transparency = new NumberSequence([new NumberSequenceKeypoint(0, 0), new NumberSequenceKeypoint(1, 1)]);
		emitter.Lifetime = new NumberRange(0.3, 0.6);
		emitter.Speed = new NumberRange(12, 22);
		emitter.SpreadAngle = new Vector2(180, 180);
		emitter.Rate = 0; // burst uniquement
		emitter.LightEmission = 1;
		emitter.LightInfluence = 0;
		emitter.Brightness = 4;
		emitter.RotSpeed = new NumberRange(-180, 180);
		emitter.Rotation = new NumberRange(0, 360);
		emitter.Parent = attachment;

		// Burst instantané
		emitter.Emit(50);

		task.delay(1.5, () => attachment.Destroy());

		// Animation de projection
		const humanoid = character?.FindFirstChildOfClass("Humanoid");
		const animator = humanoid?.FindFirstChildOfClass("Animator");
		if (animator) {
			/* 			const anim = new Instance("Animation");
			anim.AnimationId = ANIM_PARRY_ID;
			parryAnimTrack?.Stop();
			parryAnimTrack = animator.LoadAnimation(anim);
			parryAnimTrack.Priority = Enum.AnimationPriority.Action4;
			parryAnimTrack.Play(); */
		}
	});

	Players.LocalPlayer.CharacterAdded.Connect(() => {
		const camera = Workspace.CurrentCamera;
		if (camera) camera.FieldOfView = baseFov;
	});

	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		if (!exploded) {
			const wasParry = parryKnockbackCamConn !== undefined;
			parryKnockbackCamConn?.Disconnect();
			parryKnockbackCamConn = undefined;
			// Parry : reset instantané (la caméra trackait déjà le joueur, pas besoin de tween)
			// Release normal : tween fluide depuis la position cinématique de jeu
			if (wasParry) {
				parryAnimTrack?.Stop();
				parryAnimTrack = undefined;
				CameraController.BringBackPlayerCamera(0);
			} else {
				CameraController.BringBackPlayerCamera();
			}
			// resetPostProcess() retiré ici : déjà appelé dans endInput() pour la release,
			// et la FOV est reset instantanément dans PerfectParryEffectEvent pour la parry.
			// L'appel ici créait un double tween → zoom glitch.
		}
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

		const camera = Workspace.CurrentCamera;
		if (camera) {
			TweenService.Create(camera, PostProcessTI, {
				FieldOfView: baseFov - factor * (baseFov - MIN_FOV),
			}).Play();
		}
	});

	Events.ProgressUpdateEvent.OnClientEvent.Connect((progress: number) => {
		if (!isGameActive || !progressionIndicator) return;
		TweenService.Create(progressionIndicator, FillProgressBarTI, {
			Position: new UDim2(progress, 0, 0.5, 0),
		}).Play();
	});

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		if (!isGameActive) return;
		playSound(SOUND_BUTTON_EXPLODE_ID, 1); // son au moment où le bouton explose
		// 0.2s grace period : release normal encore possible
		task.delay(0.2, () => {
			if (released) return;
			// Fenêtre de perfect parry : 0.2s supplémentaires avec espace/clic
			startParryWindow();
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
	baseFov = Workspace.CurrentCamera?.FieldOfView ?? 70;
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
