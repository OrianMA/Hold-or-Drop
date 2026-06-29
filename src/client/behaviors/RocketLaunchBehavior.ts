import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { STARTING_MULTIPLIER, EXPLOSION_VIEW_DELAY, MULTIPLIER_TICK_RATE } from "shared/RocketGameConfig";
import { FormatNumber } from "shared/NumberFormat";
import { AudioConfig } from "shared/AudioConfig";
import { MusicController } from "client/audio/MusicController";
import { ButtonAnimations } from "client/behaviors/ButtonAnimations";
import {
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
let claimButton: TextButton | undefined;
let multiplierText: TextLabel | undefined;
let vignetteCanvas: CanvasGroup | undefined;
let buttonOriginalSize: UDim2 | undefined;
let claimButtonOriginalColor: Color3 | undefined;
let multiplierTextOriginalSize: number | undefined;
let multiplierTextOriginalColor: Color3 | undefined;

// Lighting effects — created once in init()
let colorCorrection: ColorCorrectionEffect | undefined;
let bloomEffect: BloomEffect | undefined;

// Per-game state
let isGameActive = false;
let released = false;
let multiplierTextSize = 0;
let shakeAmplitude = 0;
// Continuous multiplier display: the server sends a discrete value each tick; we
// lerp the shown number from the previous value to the new one over the tick so it
// passes through every intermediate number (1.01, 1.02, …) instead of jumping.
let displayedMultiplier = STARTING_MULTIPLIER;
let multiplierFrom = STARTING_MULTIPLIER;
let multiplierTo = STARTING_MULTIPLIER;
let multiplierElapsed = 0;
let shakeUndoCFrame: CFrame | undefined; // clean CFrame saved each frame to undo before next Roblox camera tick
let baseFov = 70;
let spaceConn: RBXScriptConnection | undefined;
let activatedConn: RBXScriptConnection | undefined;
let parryKnockbackCamConn: RBXScriptConnection | undefined;

// Son de parry — id centralisé dans AudioConfig.
const SOUND_PARRY_ID = AudioConfig.sfx.parry.id;

// Template persistant en SoundService : le client garde l'asset en mémoire dès le démarrage.
// Cloner ce template au moment du parry élimine le fetch CDN et le délai de buffering.
const parrySoundTemplate = (() => {
	const sound = new Instance("Sound");
	sound.Name = "ParrySoundTemplate";
	sound.SoundId = SOUND_PARRY_ID;
	sound.Volume = AudioConfig.sfx.parry.volume;
	sound.Parent = SoundService;
	return sound;
})();

// Live multiplier label text. 2 decimals below 100 ("1.00", "1.05") so the slow
// early climb is readable, 1 decimal below 1000, then k/M/B suffixes so long holds
// don't overflow the label.
function formatMultiplier(value: number): string {
	if (value < 100) return string.format("%.2f", value); // "1.00", "1.05" — précis au début
	if (value < 1000) return string.format("%.1f", value);
	return FormatNumber(value);
}

const SIZE_GROWTH_PER_UPDATE = 4;
const MAX_MULTIPLIER_SIZE_INCREASE = 80;
const MAX_SHAKE_AMPLITUDE = 0.06;
const MAX_BLOOM_INTENSITY = 1.5;
const MIN_VIGNETTE_TRANSPARENCY = 0.1;
const MIN_FOV = 52;
// Couleur du ClaimButton quand la fusée explose (il ne disparaît plus, il rougit).
const CLAIM_BUTTON_EXPLODE_COLOR = Color3.fromRGB(200, 45, 45);

const UpgradeMultiplayerTI = new TweenInfo(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const ReleaseButtonDesapearTI = new TweenInfo(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const PostProcessTI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ResetPostProcessTI = new TweenInfo(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ZoomResetTI = new TweenInfo(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ExplodeFovPunchTI = new TweenInfo(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const EXPLODE_FOV_OVERSHOOT = 18;

const PerfectParrytime = 2;

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

function buildVignette(inGameUI: ScreenGui): CanvasGroup {
	const [topLeft] = GuiService.GetGuiInset();
	const insetY = topLeft.Y;

	const canvas = new Instance("CanvasGroup");
	canvas.Name = "VignetteCanvas";
	canvas.Size = new UDim2(1, 0, 1, insetY);
	canvas.Position = new UDim2(0, 0, 0, -insetY);
	canvas.BackgroundTransparency = 1;
	canvas.GroupTransparency = 1;
	canvas.ZIndex = 1;
	canvas.Parent = inGameUI;

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
	MusicController.stopButtonMusic(); // la musique du hold s'arrête à la release
	spaceConn?.Disconnect();
	spaceConn = undefined;
	resetPostProcess();
	if (claimButton) {
		claimButton.Active = false;
		const tween = TweenService.Create(claimButton, ReleaseButtonDesapearTI, { Size: new UDim2(0, 0, 0, 0) });
		tween.Play();
		tween.Completed.Wait();
		claimButton.Visible = false;
	}
}

function startParryWindow(): void {
	isGameActive = false;
	resetPostProcess(false, true); // FOV punch + post-process instantané

	spaceConn?.Disconnect();
	spaceConn = undefined;
	activatedConn?.Disconnect();
	activatedConn = undefined;

	if (!claimButton) {
		released = true;
		return;
	}

	// Le bouton reste visible pendant la fenêtre de parry (il peut servir à parer).
	claimButton.Active = true;

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
	activatedConn = claimButton.Activated.Connect(fireParry);

	// Fin de la fenêtre de parry — le bouton reste visible (rougi par PlayerKilledEvent
	// si la partie est perdue), on coupe juste l'input de parry.
	task.delay(PerfectParrytime, () => {
		spaceConn?.Disconnect();
		spaceConn = undefined;
		activatedConn?.Disconnect();
		activatedConn = undefined;
		released = true;
		if (claimButton) claimButton.Active = false;
	});
}

// Called once at startup — all event listeners live here, gated by isGameActive
export function init(): void {
	// Comptage continu du multiplier : on interpole le nombre affiché de l'ancienne
	// valeur vers la nouvelle sur la durée d'un tick, donc il passe par tous les
	// nombres intermédiaires (lent au début, de plus en plus vite).
	RunService.RenderStepped.Connect((dt) => {
		if (!isGameActive || !multiplierText) return;
		if (multiplierElapsed < MULTIPLIER_TICK_RATE) {
			multiplierElapsed = math.min(multiplierElapsed + dt, MULTIPLIER_TICK_RATE);
			const a = multiplierElapsed / MULTIPLIER_TICK_RATE;
			displayedMultiplier = multiplierFrom + (multiplierTo - multiplierFrom) * a;
		} else {
			displayedMultiplier = multiplierTo;
		}
		multiplierText.Text = `${formatMultiplier(displayedMultiplier)}x`;
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

	// ── Camera shake — two-binding design ────────────────────────────────────────
	// Problem: Roblox's default camera in Custom mode uses an internal spring that
	// may read camera.CFrame as its starting point each tick. If we only apply shake
	// AFTER the Roblox camera update, the shaken CFrame bleeds into the spring state
	// of the next frame → the "base" look direction drifts over time.
	//
	// Fix: bind at Camera-1 to RESTORE the clean CFrame before Roblox's camera runs,
	// so its spring always starts from an unshaken base. Then bind at Camera+1 to save
	// that clean CFrame and apply a fresh shake offset.
	//
	// new CFrame(pos, lookAt) forces world-up orientation → no roll accumulation.
	RunService.BindToRenderStep("HoldOrDropShakeUndo", Enum.RenderPriority.Camera.Value - 1, () => {
		if (!shakeUndoCFrame) return;
		const camera = Workspace.CurrentCamera;
		if (camera) camera.CFrame = shakeUndoCFrame; // restore clean CFrame for Roblox camera
		shakeUndoCFrame = undefined;
	});

	RunService.BindToRenderStep("HoldOrDropShake", Enum.RenderPriority.Camera.Value + 1, () => {
		if (shakeAmplitude <= 0) {
			shakeUndoCFrame = undefined; // nothing shaken last frame, nothing to undo
			return;
		}
		const camera = Workspace.CurrentCamera;
		if (!camera) return;
		const cf = camera.CFrame; // clean CFrame just set by Roblox's camera
		shakeUndoCFrame = cf; // save so the undo binding can restore it next frame
		const newLookDir = cf.LookVector.add(cf.RightVector.mul((math.random() - 0.5) * shakeAmplitude)).add(
			cf.UpVector.mul((math.random() - 0.5) * shakeAmplitude),
		);
		camera.CFrame = new CFrame(cf.Position, cf.Position.add(newLookDir));
	});

	Events.PlayerKilledEvent.OnClientEvent.Connect(() => {
		// La fusée explose (le joueur ne meurt plus). Le bouton "claim" ne disparaît
		// pas : il devient rouge et non-cliquable (remis à l'état normal au lancement).
		spaceConn?.Disconnect();
		spaceConn = undefined;
		activatedConn?.Disconnect();
		activatedConn = undefined;
		if (claimButton) {
			claimButton.Active = false;
			claimButton.Interactable = false;
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR;
		}

		// La caméra orbitale reste sur la fusée qui explose un court instant — punch FOV
		// + shake d'impact — puis revient au joueur. Le son d'explosion vient du serveur.
		const camera = Workspace.CurrentCamera;
		if (camera) {
			camera.FieldOfView = baseFov + EXPLODE_FOV_OVERSHOOT;
			TweenService.Create(camera, ZoomResetTI, { FieldOfView: baseFov }).Play();
		}

		// Shake d'impact qui s'atténue rapidement
		shakeAmplitude = MAX_SHAKE_AMPLITUDE * 1.6;
		task.spawn(() => {
			for (let i = 0; i < 16; i++) {
				task.wait(0.03);
				shakeAmplitude *= 0.85;
			}
			shakeAmplitude = 0;
		});

		// On attend que l'explosion se joue avant de ramener la caméra au joueur.
		task.delay(EXPLOSION_VIEW_DELAY, () => {
			const cam = Workspace.CurrentCamera;
			if (cam) cam.FieldOfView = baseFov;
			CameraController.BringBackPlayerCamera();
		});
	});

	Events.PerfectParryEffectEvent.OnClientEvent.Connect(() => {
		// Le hold s'arrête et l'animation de projection parry se joue.
		ButtonAnimations.playParry();

		// Son d'explosion joué côté serveur (3D, entendu par tous)
		// Son d'épée : clone du template — asset déjà en mémoire, aucun délai de buffering
		const parrySound = parrySoundTemplate.Clone();
		parrySound.Parent = SoundService;
		parrySound.Play();
		parrySound.Ended.Connect(() => parrySound.Destroy());

		const character = Players.LocalPlayer.Character;
		const hrp = character?.FindFirstChild("HumanoidRootPart") as BasePart | undefined;

		// Caméra cinématique : au-dessus et derrière le joueur pour voir la projection.
		// L'orbite est stoppée — le tracking parry ci-dessous prend la main sur la CFrame.
		CameraController.StopOrbit();
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
	});

	Players.LocalPlayer.CharacterAdded.Connect(() => {
		const camera = Workspace.CurrentCamera;
		if (camera) camera.FieldOfView = baseFov;
	});

	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		// The HUD stays hidden until the EndGameButton (ButtonFinishGame) opens —
		// EndGameButtonBehavior re-enables it on EndGameStartEvent.
		// Safety net: stop the held pose if the game ended on death (no release/parry
		// fired). After a normal release or a parry the loop is already stopped, so
		// this is a no-op and never cuts the release/parry one-shot.
		ButtonAnimations.stop();
		if (!exploded) {
			const wasParry = parryKnockbackCamConn !== undefined;
			parryKnockbackCamConn?.Disconnect();
			parryKnockbackCamConn = undefined;
			// Parry : reset instantané (la caméra trackait déjà le joueur, pas besoin de tween)
			// Release normal : tween fluide depuis la position cinématique de jeu
			if (wasParry) {
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

	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		if (!isGameActive || !multiplierText) return;

		// Nouvelle cible : le nombre affiché va monter en continu vers `multiplier`
		// sur la durée d'un tick (voir la boucle RenderStepped dans init).
		multiplierFrom = displayedMultiplier;
		multiplierTo = multiplier;
		multiplierElapsed = 0;

		multiplierTextSize += SIZE_GROWTH_PER_UPDATE;

		const factor = math.clamp(
			(multiplierTextSize - (multiplierTextOriginalSize ?? 0)) / MAX_MULTIPLIER_SIZE_INCREASE,
			0,
			1,
		);
		const capturedColor = (multiplierTextOriginalColor ?? new Color3(1, 1, 1)).Lerp(new Color3(1, 0, 0), factor);

		// Snapshot pour la popup de fin (taille + couleur au moment de la fin)
		MultiplierVisuals.capture(multiplierTextSize, capturedColor);

		// Bump de taille + virage au rouge (la valeur, elle, monte en continu)
		TweenService.Create(multiplierText, UpgradeMultiplayerTI, {
			TextSize: multiplierTextSize,
			TextColor3: capturedColor,
		}).Play();

		// Effets ambiants immédiats (game-feel)
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

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		if (!isGameActive) return;
		MusicController.stopButtonMusic(); // la musique du hold s'arrête à l'instant de l'explosion
		// 0.2s grace period : release normal encore possible
		task.delay(0.2, () => {
			if (released) return;
			// Fenêtre de perfect parry : 0.2s supplémentaires avec espace/clic
			startParryWindow();
		});
	});
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(inGameUI: ScreenGui): void {
	const popup = inGameUI.WaitForChild("RocketLaunch") as Frame;
	const claimButtonFrame = popup.WaitForChild("ClaimButtonFrame") as Frame;
	claimButton = claimButtonFrame.WaitForChild("ClaimButton") as TextButton;
	multiplierText = popup.WaitForChild("MultiplierText") as TextLabel;

	// Save original sizes/colors on first run so we can restore each game
	if (!buttonOriginalSize) buttonOriginalSize = claimButton.Size;
	if (!claimButtonOriginalColor) claimButtonOriginalColor = claimButton.BackgroundColor3;
	if (!multiplierTextOriginalSize) multiplierTextOriginalSize = multiplierText.TextSize;
	if (!multiplierTextOriginalColor) multiplierTextOriginalColor = multiplierText.TextColor3;
	if (!vignetteCanvas) vignetteCanvas = buildVignette(inGameUI);

	// Reset per-game state
	baseFov = Workspace.CurrentCamera?.FieldOfView ?? 70;
	isGameActive = true;
	released = false;
	MusicController.playButtonMusic(); // début du hold → musique du bouton en boucle
	ButtonAnimations.playHold(); // remplace la pose "interact" : le perso appuie et reste sur le bouton
	multiplierText.TextSize = multiplierTextOriginalSize;
	multiplierText.TextColor3 = multiplierTextOriginalColor;
	multiplierTextSize = multiplierTextOriginalSize;
	// Le compteur continu redémarre à 1.00x.
	displayedMultiplier = STARTING_MULTIPLIER;
	multiplierFrom = STARTING_MULTIPLIER;
	multiplierTo = STARTING_MULTIPLIER;
	multiplierElapsed = MULTIPLIER_TICK_RATE;
	MultiplierVisuals.clear();
	resetPostProcess(true);

	// Restore button to full size, normal colour and re-enable it
	claimButton.Size = buttonOriginalSize;
	claimButton.BackgroundColor3 = claimButtonOriginalColor;
	claimButton.Interactable = true;
	claimButton.Active = true;
	claimButton.Visible = true;

	// Reset UI
	multiplierText.Text = `${formatMultiplier(STARTING_MULTIPLIER)}x`;

	// Clean up any leftover connections from a previous game
	spaceConn?.Disconnect();
	activatedConn?.Disconnect();

	const fireRelease = () => {
		if (!isGameActive || released) return;
		endInput();
		ButtonAnimations.playRelease(); // le perso relâche le bouton
		Events.ReleaseButtonEvent.FireServer();
	};

	activatedConn = claimButton.Activated.Connect(fireRelease);
}
