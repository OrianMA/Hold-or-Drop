import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { STARTING_MULTIPLIER, EXPLOSION_VIEW_DELAY, MULTIPLIER_TICK_RATE } from "shared/RocketGameConfig";
import { FormatNumber } from "shared/NumberFormat";
import { AudioConfig } from "shared/AudioConfig";
import { MusicController } from "client/audio/MusicController";
import { ButtonAnimations } from "client/behaviors/ButtonAnimations";
import { RocketSteerController } from "client/behaviors/RocketSteerController";
import {
	ContentProvider,
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
let resultMultiplierText: TextLabel | undefined;
// Popup "gain verrouillé" révélé au claim : CanvasGroup (fade) + Frame qui monte.
let claimPopupGroup: CanvasGroup | undefined;
let claimPopup: Frame | undefined;
let claimPopupResult: TextLabel | undefined;
let claimPopupOriginalPos: UDim2 | undefined; // position "affichée" (cible de la montée), lue une fois
let claimPopupRevealId = 0; // jeton anti-collision : invalide un timer de disparition si un reset/reveal survient
let claimPopupWarmed = false; // pré-chauffage de la texture du CanvasGroup fait une seule fois
let buttonOriginalSize: UDim2 | undefined;
let claimButtonOriginalColor: Color3 | undefined;
let multiplierTextOriginalSize: number | undefined;
let multiplierTextOriginalColor: Color3 | undefined;

// Lighting effects — created once in init()
let bloomEffect: BloomEffect | undefined;

// Per-game state
let isGameActive = false;
let released = false;
let hasClaimed = false; // le joueur a verrouillé son multiplicateur (claim) pour cette partie
let multiplierTextSize = 0;
// Aperçu live du gain "si je claim maintenant" (floor(EffectiveBaseCash × multiplicateur)).
let resultBaseCash = 100; // EffectiveBaseCash du joueur, lu une fois au début de partie
let lastResultMultiplier = STARTING_MULTIPLIER; // dernier multiplicateur pour lequel le texte a été rafraîchi
let resultUpdateElapsed = 0; // temps écoulé depuis le dernier rafraîchissement (throttle)
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

// Bascule musicale à l'altitude : on capture le Y de la fusée au décollage, puis une fois
// qu'elle a grimpé HIGH_ALTITUDE_MUSIC_THRESHOLD studs, on crossfade la BGM vers la piste
// haute altitude (une seule fois par run). Pendant un run la caméra suit la fusée, donc son
// CameraSubject EST la part de la fusée : on lit son Y en direct, sans plomberie réseau.
const HIGH_ALTITUDE_MUSIC_THRESHOLD = 50;
let rocketMusicSubject: BasePart | undefined;
let rocketBaselineY = 0;
let highAltitudeReached = false;

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

// Son de cash joué au moment du claim (au lieu du clic UI générique — le ClaimButton
// porte l'attribut NoUiClick pour que UiClickSound le saute). Template préchargé, cloné
// à chaque claim pour éviter tout fetch CDN.
const claimCashSoundTemplate = (() => {
	const sound = new Instance("Sound");
	sound.Name = "ClaimCashSoundTemplate";
	sound.SoundId = AudioConfig.sfx.moneyGain.id;
	sound.Volume = AudioConfig.sfx.moneyGain.volume;
	sound.Parent = SoundService;
	return sound;
})();

function playClaimCashSound(): void {
	const sound = claimCashSoundTemplate.Clone();
	sound.Parent = SoundService;
	sound.Play();
	sound.Ended.Connect(() => sound.Destroy());
}

// Position "en bas" du popup : sa position d'origine décalée de CLAIM_POPUP_RISE px vers le bas.
function claimPopupLoweredPos(): UDim2 {
	const p = claimPopupOriginalPos ?? new UDim2();
	return new UDim2(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + CLAIM_POPUP_RISE);
}

// Pré-chauffage : un CanvasGroup n'alloue sa texture interne qu'à son premier rendu
// (GroupTransparency < 1) ; cette première frame est basse résolution → reveal flou. On force
// donc un rendu invisible-à-l'oeil (0.99 = 1% d'opacité) au démarrage pour allouer la texture,
// puis on recoupe le rendu (retour à 1) : aucun coût permanent. Fait une seule fois par session.
function warmUpClaimPopup(): void {
	if (claimPopupWarmed || !claimPopupGroup) return;
	claimPopupWarmed = true;
	const group = claimPopupGroup;
	const id = claimPopupRevealId;
	group.GroupTransparency = 0.99;
	task.delay(0.3, () => {
		// Si rien ne s'est affiché entre-temps (id inchangé), on coupe le rendu.
		if (id === claimPopupRevealId) group.GroupTransparency = 1;
	});
}

// État de repos : popup invisible (fade complet) et abaissé, prêt à monter au claim.
// Bump du jeton pour qu'un timer de disparition en attente ne touche pas un futur reveal.
function hideClaimPopup(): void {
	claimPopupRevealId += 1;
	if (claimPopupGroup) claimPopupGroup.GroupTransparency = 1;
	if (claimPopup) claimPopup.Position = claimPopupLoweredPos();
}

// Reveal au claim : on écrit le gain verrouillé, fondu entrant + montée, puis après
// CLAIM_POPUP_HOLD s le popup se refond (fade out) — sauf si un reset/reveal l'a invalidé.
function revealClaimPopup(amount: number): void {
	if (!claimPopupGroup || !claimPopup || !claimPopupResult || !claimPopupOriginalPos) return;
	claimPopupRevealId += 1;
	const myId = claimPopupRevealId;
	claimPopupResult.Text = `$${FormatNumber(amount)}`;
	// Repart de l'état de repos avant d'animer (au cas où un tween précédent traînerait).
	claimPopupGroup.GroupTransparency = 1;
	claimPopup.Position = claimPopupLoweredPos();
	TweenService.Create(claimPopupGroup, ClaimPopupTI, { GroupTransparency: 0 }).Play();
	TweenService.Create(claimPopup, ClaimPopupTI, { Position: claimPopupOriginalPos }).Play();

	task.delay(CLAIM_POPUP_HOLD, () => {
		if (myId !== claimPopupRevealId || !claimPopupGroup) return; // reset/reveal survenu entre-temps
		TweenService.Create(claimPopupGroup, ClaimPopupFadeTI, { GroupTransparency: 1 }).Play();
	});
}

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
const MAX_SHAKE_AMPLITUDE = 0.06; // shake d'impact à l'explosion (PlayerKilledEvent)
// Tremblement du décollage : fort au début (poussée/atmosphère) puis s'atténue vers 0
// (on monte vers l'espace, c'est de plus en plus calme).
const LAUNCH_SHAKE_START = 0.06;
const LAUNCH_SHAKE_DECAY = 0.6; // atténuation par seconde (multiplicative)
const MAX_BLOOM_INTENSITY = 1.5;
// Couleur du ClaimButton quand la fusée explose (il ne disparaît plus, il rougit).
// Aussi appliquée au claim : le bouton devient rouge dès qu'on verrouille.
const CLAIM_BUTTON_EXPLODE_COLOR = Color3.fromRGB(200, 45, 45);

// Aperçu de gain : on ne rafraîchit le texte que si le multiplicateur a bougé d'au moins
// RESULT_UPDATE_MULT_STEP ET qu'au moins RESULT_UPDATE_MIN_DELAY s'est écoulé (anti-spam).
const RESULT_UPDATE_MULT_STEP = 0.01;
const RESULT_UPDATE_MIN_DELAY = 0.2;

const UpgradeMultiplayerTI = new TweenInfo(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const PostProcessTI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ResetPostProcessTI = new TweenInfo(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ZoomResetTI = new TweenInfo(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ExplodeFovPunchTI = new TweenInfo(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const EXPLODE_FOV_OVERSHOOT = 18;

// Reveal du popup de gain au claim : le popup part un peu plus bas et transparent, puis
// monte de CLAIM_POPUP_RISE px en fondu (fade via CanvasGroup) jusqu'à sa position d'origine.
const CLAIM_POPUP_RISE = 45;
const CLAIM_POPUP_HOLD = 3; // s d'affichage avant la disparition
const ClaimPopupTI = new TweenInfo(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const ClaimPopupFadeTI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

const PerfectParrytime = 2;

function resetPostProcess(instant = false, explode = false): void {
	const ti = instant || explode ? new TweenInfo(0) : ResetPostProcessTI;
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
	// Précharge le son de cash pour que même le TOUT premier claim de la session soit
	// instantané (les suivants sont déjà en cache). 100 % client : aucune latence réseau.
	task.spawn(() => {
		pcall(() => ContentProvider.PreloadAsync([claimCashSoundTemplate]));
	});

	// Comptage continu du multiplier : on interpole le nombre affiché de l'ancienne
	// valeur vers la nouvelle sur la durée d'un tick, donc il passe par tous les
	// nombres intermédiaires (lent au début, de plus en plus vite).
	RunService.RenderStepped.Connect((dt) => {
		if (!isGameActive || !multiplierText) return;

		// Une fois la fusée montée de HIGH_ALTITUDE_MUSIC_THRESHOLD studs au-dessus du pad,
		// on crossfade vers la piste haute altitude (une seule fois par run).
		if (
			rocketMusicSubject &&
			!highAltitudeReached &&
			rocketMusicSubject.Position.Y - rocketBaselineY >= HIGH_ALTITUDE_MUSIC_THRESHOLD
		) {
			highAltitudeReached = true;
			MusicController.enterHighAltitude();
		}

		if (multiplierElapsed < MULTIPLIER_TICK_RATE) {
			multiplierElapsed = math.min(multiplierElapsed + dt, MULTIPLIER_TICK_RATE);
			const a = multiplierElapsed / MULTIPLIER_TICK_RATE;
			displayedMultiplier = multiplierFrom + (multiplierTo - multiplierFrom) * a;
		} else {
			displayedMultiplier = multiplierTo;
		}
		multiplierText.Text = `${formatMultiplier(displayedMultiplier)}x`;

		// Aperçu live du gain "si je claim maintenant" : floor(EffectiveBaseCash × mult).
		// Rafraîchi seulement quand le multiplicateur a bougé d'au moins RESULT_UPDATE_MULT_STEP
		// ET qu'au moins RESULT_UPDATE_MIN_DELAY s'est écoulé. Figé une fois qu'on a claim.
		if (resultMultiplierText && !hasClaimed) {
			resultUpdateElapsed += dt;
			if (
				resultUpdateElapsed >= RESULT_UPDATE_MIN_DELAY &&
				math.abs(displayedMultiplier - lastResultMultiplier) >= RESULT_UPDATE_MULT_STEP
			) {
				lastResultMultiplier = displayedMultiplier;
				resultUpdateElapsed = 0;
				resultMultiplierText.Text = `$${FormatNumber(math.floor(resultBaseCash * displayedMultiplier))}`;
			}
		}

		// Le tremblement de décollage s'atténue avec le temps (fort au début → calme).
		shakeAmplitude = shakeAmplitude * math.max(0, 1 - LAUNCH_SHAKE_DECAY * dt);
	});

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
		// Fin de partie : la fusée n'existe plus → on stoppe la montée du multiplierText
		// (vrai aussi bien après un claim qu'après une perte).
		isGameActive = false;
		RocketSteerController.stop(); // fin du vol : plus de pilotage
		MusicController.stopRunMusic(); // coupe la musique du run (cas claim : pas de ButtonExplodedEvent)
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
		// Safety net: stop the held pose if the game ended on explosion (no parry fired).
		// After a claim or a parry the loop is already stopped, so this is a no-op and
		// never cuts the parry one-shot.
		isGameActive = false;
		RocketSteerController.stop(); // filet de sécurité : coupe le pilotage à toute fin de partie
		ButtonAnimations.stop();
		if (!exploded) {
			const wasParry = parryKnockbackCamConn !== undefined;
			parryKnockbackCamConn?.Disconnect();
			parryKnockbackCamConn = undefined;
			// Parry réussie : reset instantané (la caméra trackait déjà le joueur, pas de tween).
			if (wasParry) {
				CameraController.BringBackPlayerCamera(0);
			} else {
				CameraController.BringBackPlayerCamera();
			}
			// resetPostProcess() n'est pas appelé ici : la FOV est déjà reset instantanément
			// dans PerfectParryEffectEvent pour la parry ; l'appeler créait un double tween → glitch.
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

		// Effets ambiants : pas de vignette/teinte rouge ni de zoom FOV progressif pendant
		// le décollage ; juste un léger bloom. Le tremblement est géré (et atténué) dans la
		// boucle RenderStepped, pas ici.
		if (bloomEffect) {
			TweenService.Create(bloomEffect, PostProcessTI, {
				Intensity: factor * MAX_BLOOM_INTENSITY,
			}).Play();
		}
	});

	// Claim confirmé par le serveur : on FIGE le gain verrouillé EXACT (= payout serveur,
	// floor(EffectiveBaseCash × claimedMultiplier)). Mise à jour immédiate, sans throttle.
	// La fusée continue et le multiplierText grimpe encore, mais ce texte reste figé.
	Events.ClaimAcceptedEvent.OnClientEvent.Connect((claimedMultiplier: number) => {
		const claimedCash = math.floor(resultBaseCash * claimedMultiplier);
		if (resultMultiplierText) {
			resultMultiplierText.Text = `$${FormatNumber(claimedCash)}`;
			resultMultiplierText.Visible = true;
		}
		// Popup de gain verrouillé : fondu entrant + montée avec le montant exact.
		revealClaimPopup(claimedCash);
	});

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		if (!isGameActive) return;
		MusicController.stopRunMusic(); // la musique du run s'arrête à l'instant de l'explosion
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
	resultMultiplierText = popup.WaitForChild("ResultMultiplierText") as TextLabel;

	// Popup de gain (fade + montée) révélé au claim.
	claimPopupGroup = popup.WaitForChild("CanvasGroup") as CanvasGroup;
	claimPopup = claimPopupGroup.WaitForChild("ClaimButtonPopup") as Frame;
	claimPopupResult = claimPopup.WaitForChild("ResultText") as TextLabel;
	if (!claimPopupOriginalPos) claimPopupOriginalPos = claimPopup.Position;

	// Le ClaimButton joue son propre son (cash) au clic → on demande à UiClickSound de
	// sauter le clic générique pour ce bouton (attribut lu au moment du clic).
	claimButton.SetAttribute("NoUiClick", true);

	// Save original sizes/colors on first run so we can restore each game
	if (!buttonOriginalSize) buttonOriginalSize = claimButton.Size;
	if (!claimButtonOriginalColor) claimButtonOriginalColor = claimButton.BackgroundColor3;
	if (!multiplierTextOriginalSize) multiplierTextOriginalSize = multiplierText.TextSize;
	if (!multiplierTextOriginalColor) multiplierTextOriginalColor = multiplierText.TextColor3;

	// Reset per-game state
	baseFov = Workspace.CurrentCamera?.FieldOfView ?? 70;
	isGameActive = true;
	released = false;
	hasClaimed = false;
	// EffectiveBaseCash (attribut répliqué) : base du gain affiché dans ResultMultiplierText.
	// Lu une fois par partie — comme côté serveur, il ne bouge pas en cours de hold.
	resultBaseCash = (Players.LocalPlayer.GetAttribute("EffectiveBaseCash") as number | undefined) ?? 100;
	lastResultMultiplier = STARTING_MULTIPLIER;
	resultUpdateElapsed = 0;
	// Bascule musicale à l'altitude : baseline = Y de la fusée maintenant (encore sur le pad).
	// La caméra suit déjà la fusée (StartOrbit), donc son CameraSubject EST la part de la fusée ;
	// on lit son Y en direct dans la boucle RenderStepped pour détecter le seuil.
	highAltitudeReached = false;
	const camSubject = Workspace.CurrentCamera?.CameraSubject;
	if (camSubject && camSubject.IsA("BasePart")) {
		rocketMusicSubject = camSubject;
		rocketBaselineY = camSubject.Position.Y;
	} else {
		rocketMusicSubject = undefined;
	}
	MusicController.startRun(); // début du hold → la BGM de base continue de jouer
	ButtonAnimations.playHold(); // remplace la pose "interact" : le perso appuie et reste sur le bouton
	RocketSteerController.start(); // le mouvement natif gauche/droite pilote la fusée pendant le vol
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
	// Décollage : gros tremblement au départ, atténué ensuite par la boucle RenderStepped.
	shakeAmplitude = LAUNCH_SHAKE_START;

	// Restore button to full size, normal colour and re-enable it
	claimButton.Size = buttonOriginalSize;
	claimButton.BackgroundColor3 = claimButtonOriginalColor;
	claimButton.Interactable = true;
	claimButton.Active = true;
	claimButton.Visible = true;

	// Aperçu de gain visible dès le décollage : "si je claim maintenant" = baseCash × 1.00x.
	// Il grimpe ensuite (throttlé) dans la boucle RenderStepped, puis se fige au claim.
	resultMultiplierText.Text = `$${FormatNumber(math.floor(resultBaseCash * STARTING_MULTIPLIER))}`;
	resultMultiplierText.Visible = true;

	// Popup de gain caché tant qu'on n'a pas claim (fade complet + abaissé).
	hideClaimPopup();
	// Pré-chauffe la texture du CanvasGroup (une seule fois) pour éviter un premier reveal flou.
	warmUpClaimPopup();

	// Reset UI
	multiplierText.Text = `${formatMultiplier(STARTING_MULTIPLIER)}x`;

	// Clean up any leftover connections from a previous game
	spaceConn?.Disconnect();
	activatedConn?.Disconnect();

	// Claim : le joueur VERROUILLE son multiplicateur. La partie NE s'arrête PAS —
	// la fusée continue de monter (le multiplierText grimpe encore) jusqu'à l'explosion.
	// Le bouton devient rouge (comme à l'explosion) et non-cliquable (pas de double claim) ;
	// on joue le son de cash ; le serveur renvoie la valeur verrouillée exacte via
	// ClaimAcceptedEvent (figée dans ResultMultiplierText).
	const fireClaim = () => {
		if (!isGameActive || hasClaimed) return;
		hasClaimed = true;
		if (claimButton) {
			claimButton.Active = false;
			claimButton.Interactable = false;
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR;
		}
		playClaimCashSound();
		Events.ClaimButtonEvent.FireServer();
	};

	activatedConn = claimButton.Activated.Connect(fireClaim);
}
