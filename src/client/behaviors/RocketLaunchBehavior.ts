import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { STARTING_MULTIPLIER, EXPLOSION_VIEW_DELAY, MULTIPLIER_TICK_RATE } from "shared/RocketGameConfig";
import { MEGA_ROCKET_BASE_CASH_MULT, hasMegaRocket } from "shared/MegaRocketConfig";
import { FormatNumber } from "shared/NumberFormat";
import { playCashSound, preloadCashSound } from "client/audio/CashSound";
import { MusicController } from "client/audio/MusicController";
import { ButtonAnimations } from "client/behaviors/ButtonAnimations";
import { RocketSteerController } from "client/behaviors/RocketSteerController";
import { MoneyBurst } from "client/ui/MoneyBurst";
import { ClaimFlashText } from "client/ui/ClaimFlashText";
import { CriticalRain } from "client/ui/CriticalRain";
import { InformationText } from "client/ui/InformationText";
import { ContentProvider, Lighting, Players, RunService, TweenService, Workspace } from "@rbxts/services";

// UI refs — assigned on first setup(), never change after
let claimButton: TextButton | undefined;
// Les deux dégradés du ClaimButton : "Claim" pendant le vol, "Home" une fois le gain
// verrouillé. On ne bascule de l'un à l'autre qu'au réarmement "Go Home" (quand la
// couleur du bouton redevient normale), pas pendant l'assombrissement du claim.
let claimGradient: UIGradient | undefined;
let homeGradient: UIGradient | undefined;
// Le libellé posé sur le ClaimButton : "Claim" pendant le vol, "Go Home" une fois le
// gain verrouillé (le bouton se réarme alors pour rentrer à la base).
let claimLabel: TextLabel | undefined;
let claimLabelOriginalText: string | undefined;
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

// Pulse d'onboarding du bouton Claim : tant que le joueur n'a pas encaissé quelques
// fois, le bouton respire (taille + halo) pour que le geste soit impossible à rater.
// Compteur en mémoire, remis à zéro à chaque session — aucun état serveur.
let claimPulseTween: Tween | undefined;
let claimPulseStroke: UIStroke | undefined;
let claimPulseStrokeTween: Tween | undefined;
let sessionClaimCount = 0;

// Pendant le tutorial c'est lui qui met le bouton Claim en avant (TutorialFocus) : deux
// animations concurrentes sur le même bouton se battraient.
let tutorialActive = false;

// Lighting effects — created once in init()
let bloomEffect: BloomEffect | undefined;

// Per-game state
let isGameActive = false;
let hasClaimed = false; // le joueur a verrouillé son multiplicateur (claim) pour cette partie
// Perfect Claim annoncé par le serveur au claim : le flash rouge n'est joué qu'à
// l'explosion (le ×3 est déjà dans le gain, c'est le boom qui le "valide" à l'écran).
// Le Critical Claim, lui, part tout de suite au claim (voir ClaimAcceptedEvent).
let perfectClaimPending = false;
let isGoHomeMode = false; // le bouton est réarmé en "Go Home" (rentrer à la base)
let runId = 0; // incrémenté à chaque partie — invalide les timers d'une partie précédente
let multiplierTextSize = 0;
// Chauffe du multiplicateur : 0 au décollage, MULTIPLIER_HEAT_UPDATES quand le texte est
// au rouge plein. Compteur explicite plutôt que déduit de TextSize — le label est en
// TextScaled dans Studio, donc sa TextSize ne veut plus rien dire visuellement.
let multiplierHeat = 0;
// Verrou de couleur : une fois le rouge plein atteint, on n'y retouche plus du tout de
// la partie (plus aucun tween sur TextColor3). Sans ça le label restait la cible d'un
// tween par tick jusqu'à la fin du vol, alors que la couleur ne bougeait plus.
let multiplierColorLocked = false;
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
let activatedConn: RBXScriptConnection | undefined;

// Bascule musicale à l'altitude : on capture le Y de la fusée au décollage, puis une fois
// qu'elle a grimpé HIGH_ALTITUDE_MUSIC_THRESHOLD studs, on crossfade la BGM vers la piste
// haute altitude (une seule fois par run). Pendant un run la caméra suit la fusée, donc son
// CameraSubject EST la part de la fusée : on lit son Y en direct, sans plomberie réseau.
const HIGH_ALTITUDE_MUSIC_THRESHOLD = 65;
let rocketMusicSubject: BasePart | undefined;
let rocketBaselineY = 0;
let highAltitudeReached = false;

// Son de cash joué au moment du claim (au lieu du clic UI générique — le ClaimButton
// porte l'attribut NoUiClick pour que UiClickSound le saute). Voir client/audio/CashSound.
function playClaimCashSound(): void {
	playCashSound();
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
// Couleur du multiplicateur pendant le vol : il part d'un rouge clair et FONCE vers un
// rouge profond — il ne passe jamais par une autre teinte. Les deux bornes sont définies
// ici et pas lues sur le label : la couleur réglée dans Studio servait de point de départ,
// donc toute retouche de la GUI changeait la teinte de départ du vol.
const MULTIPLIER_COLOR_START = Color3.fromRGB(255, 120, 110);
const MULTIPLIER_COLOR_FULL = Color3.fromRGB(190, 0, 0);
// Nombre de ticks serveur pour atteindre le rouge plein (~5 s à MULTIPLIER_TICK_RATE).
const MULTIPLIER_HEAT_UPDATES = 20;
const MAX_SHAKE_AMPLITUDE = 0.06; // shake d'impact à l'explosion (PlayerKilledEvent)
// Tremblement du décollage : fort au début (poussée/atmosphère) puis s'atténue vers 0
// (on monte vers l'espace, c'est de plus en plus calme).
const LAUNCH_SHAKE_START = 0.06;
const LAUNCH_SHAKE_DECAY = 0.6; // atténuation par seconde (multiplicative)
const MAX_BLOOM_INTENSITY = 1.5;
// Couleur du ClaimButton quand la fusée explose (il ne disparaît plus, il rougit).
// Aussi appliquée au claim : le bouton devient rouge dès qu'on verrouille.
const CLAIM_BUTTON_EXPLODE_COLOR = Color3.fromRGB(200, 45, 45);
// Après un claim le bouton se réarme en "Go Home" : court délai anti-double-clic, puis il
// redevient cliquable pour rentrer à la base (fusée stoppée, caméra rendue au joueur).
const CLAIM_REARM_DELAY = 0.6;
const GO_HOME_LABEL = "Go Home";

// Nombre de claims après lequel le pulse d'onboarding s'arrête définitivement (session).
const CLAIM_PULSE_RUNS = 3;
// Amplitude du gonflement du bouton pendant le pulse.
const CLAIM_PULSE_SCALE = 1.08;
const ClaimPulseTI = new TweenInfo(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true);

// Aperçu de gain : on ne rafraîchit le texte que si le multiplicateur a bougé d'au moins
// RESULT_UPDATE_MULT_STEP ET qu'au moins RESULT_UPDATE_MIN_DELAY s'est écoulé (anti-spam).
const RESULT_UPDATE_MULT_STEP = 0.01;
const RESULT_UPDATE_MIN_DELAY = 0.2;

const UpgradeMultiplayerTI = new TweenInfo(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const PostProcessTI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ResetPostProcessTI = new TweenInfo(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ZoomResetTI = new TweenInfo(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const EXPLODE_FOV_OVERSHOOT = 18;

// Reveal du popup de gain au claim : le popup part un peu plus bas et transparent, puis
// monte de CLAIM_POPUP_RISE px en fondu (fade via CanvasGroup) jusqu'à sa position d'origine.
const CLAIM_POPUP_RISE = 45;
const CLAIM_POPUP_HOLD = 3; // s d'affichage avant la disparition
const ClaimPopupTI = new TweenInfo(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const ClaimPopupFadeTI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

function resetPostProcess(instant = false): void {
	const ti = instant ? new TweenInfo(0) : ResetPostProcessTI;
	if (bloomEffect) {
		TweenService.Create(bloomEffect, ti, { Intensity: 0 }).Play();
	}
	const camera = Workspace.CurrentCamera;
	if (camera) {
		const fovTi = instant ? new TweenInfo(0) : ZoomResetTI;
		TweenService.Create(camera, fovTi, { FieldOfView: baseFov }).Play();
	}
	shakeAmplitude = 0;
}

export function setTutorialActive(active: boolean): void {
	tutorialActive = active;
	if (active) stopClaimPulse();
}

// Called once at startup — all event listeners live here, gated by isGameActive
export function init(): void {
	// Précharge le son de cash pour que même le TOUT premier claim de la session soit
	// instantané (les suivants sont déjà en cache). 100 % client : aucune latence réseau.
	preloadCashSound();
	// Même logique pour l'image des billets de l'explosion de cash au claim.
	MoneyBurst.preload();
	CriticalRain.preload();

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
		// Perfect Claim : la fusée vient d'exploser juste après le claim — c'est MAINTENANT
		// que le flash rouge tombe, sur le boom (le ×3 est déjà verrouillé dans le gain).
		if (perfectClaimPending) {
			perfectClaimPending = false;
			ClaimFlashText.showPerfect();
		}
		// La fusée explose (le joueur ne meurt plus). Le bouton "claim" ne disparaît
		// pas : il devient rouge et non-cliquable (remis à l'état normal au lancement).
		// Fin de partie : la fusée n'existe plus → on stoppe la montée du multiplierText
		// (vrai aussi bien après un claim qu'après une perte).
		isGameActive = false;
		isGoHomeMode = false; // la fusée a explosé : le "Go Home" n'a plus lieu d'être
		stopClaimPulse(); // fin de partie : plus de respiration sur un bouton éteint
		RocketSteerController.stop(); // fin du vol : plus de pilotage
		MusicController.stopRunMusic(); // coupe la musique du run (cas claim : pas de ButtonExplodedEvent)
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

	Players.LocalPlayer.CharacterAdded.Connect(() => {
		const camera = Workspace.CurrentCamera;
		if (camera) camera.FieldOfView = baseFov;
	});

	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		// The HUD stays hidden until the EndGameButton (ButtonFinishGame) opens —
		// EndGameButtonBehavior re-enables it on EndGameStartEvent.
		// Safety net: stop the held pose if the game ended on explosion.
		// After a claim the loop is already stopped, so this is a no-op.
		isGameActive = false;
		InformationText.setInFlight(false); // les bandeaux remontent à leur place
		RocketSteerController.stop(); // filet de sécurité : coupe le pilotage à toute fin de partie
		ButtonAnimations.stop();
		// Fin sans explosion (cas défensif) : la caméra n'a pas été ramenée par
		// PlayerKilledEvent, on la rend au joueur ici.
		if (!exploded) CameraController.BringBackPlayerCamera();
		print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
	});

	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		if (!isGameActive || !multiplierText) return;

		// Nouvelle cible : le nombre affiché va monter en continu vers `multiplier`
		// sur la durée d'un tick (voir la boucle RenderStepped dans init).
		multiplierFrom = displayedMultiplier;
		multiplierTo = multiplier;
		multiplierElapsed = 0;

		// Taille bornée : sans plafond elle grimpe indéfiniment sur un vol long, et c'est
		// elle qu'on passe à la popup de fin (qui, elle, n'est PAS en TextScaled).
		multiplierTextSize = math.min(
			multiplierTextSize + SIZE_GROWTH_PER_UPDATE,
			(multiplierTextOriginalSize ?? 0) + MAX_MULTIPLIER_SIZE_INCREASE,
		);

		multiplierHeat = math.min(multiplierHeat + 1, MULTIPLIER_HEAT_UPDATES);
		const factor = multiplierHeat / MULTIPLIER_HEAT_UPDATES;

		// Couleur : on chauffe du rouge clair vers le rouge plein, puis on VERROUILLE.
		// Au dernier palier on écrit MULTIPLIER_COLOR_FULL directement au lieu de le
		// tweener — UpgradeMultiplayerTI est en EasingStyle.Back, dont le dépassement
		// pousse les canaux sous zéro (mesuré : 190,-1,-1) avant de revenir.
		const capturedColor = multiplierColorLocked
			? MULTIPLIER_COLOR_FULL
			: MULTIPLIER_COLOR_START.Lerp(MULTIPLIER_COLOR_FULL, factor);

		// Snapshot pour la popup de fin (taille + couleur au moment de la fin)
		MultiplierVisuals.capture(multiplierTextSize, capturedColor);

		if (!multiplierColorLocked && factor >= 1) {
			multiplierColorLocked = true;
			multiplierText.TextColor3 = MULTIPLIER_COLOR_FULL;
		}

		// Bump de taille (la valeur, elle, monte en continu). La couleur n'entre dans le
		// tween que tant qu'elle chauffe : une fois verrouillée, plus rien ne l'écrit.
		const goal: Partial<WritableInstanceProperties<TextLabel>> = { TextSize: multiplierTextSize };
		if (!multiplierColorLocked) goal.TextColor3 = capturedColor;
		TweenService.Create(multiplierText, UpgradeMultiplayerTI, goal).Play();

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
	Events.ClaimAcceptedEvent.OnClientEvent.Connect(
		(claimedMultiplier: number, perfect: boolean, critical: boolean, claimedBaseCash: number) => {
			// Perfect Claim : le ×3 est déjà dans le BASE CASH reçu (le multiplicateur, lui,
			// ne bouge pas). On ne l'annonce PAS tout de suite — le flash rouge part à
			// l'explosion, quelques dixièmes plus tard.
			perfectClaimPending = perfect;
			// Critical Claim (12 %) : le ×10 est déjà dans le base cash reçu, et il n'a
			// rien à voir avec l'explosion — le flash doré part MAINTENANT, sur le claim. Si
			// un perfect suit, son flash rouge s'empilera sous celui-ci (ClaimFlashText).
			// La petite pluie d'icônes tombe sur la même frame que le texte.
			if (critical) {
				ClaimFlashText.showCritical();
				CriticalRain.play();
			}
			// Base cash verrouillé (bonus inclus) : c'est lui qui porte le gain figé.
			resultBaseCash = claimedBaseCash;
			const claimedCash = math.floor(claimedBaseCash * claimedMultiplier);
			if (resultMultiplierText) {
				resultMultiplierText.Text = `$${FormatNumber(claimedCash)}`;
				resultMultiplierText.Visible = true;
			}
			// Popup de gain verrouillé : fondu entrant + montée avec le montant exact.
			revealClaimPopup(claimedCash);
			// Gerbe de billets 2D : part du centre de l'écran, se disperse d'un coup, retombe.
			MoneyBurst.play();
		},
	);

	// La fusée explose sans claim : la partie est finie côté client (le claim ne peut
	// plus rien verrouiller). PlayerKilledEvent, qui suit immédiatement, gère la caméra,
	// le shake et l'état du bouton — ici on coupe juste la musique et le bloom.
	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		if (!isGameActive) return;
		isGameActive = false;
		MusicController.stopRunMusic(); // la musique du run s'arrête à l'instant de l'explosion
		if (bloomEffect) bloomEffect.Intensity = 0;
	});
}

// Arrête le pulse et remet le bouton à sa taille / son halo d'origine. Idempotent :
// appelable même si aucun pulse ne tourne.
function stopClaimPulse(): void {
	claimPulseTween?.Cancel();
	claimPulseTween = undefined;
	claimPulseStrokeTween?.Cancel();
	claimPulseStrokeTween = undefined;
	if (claimPulseStroke) claimPulseStroke.Enabled = false;
	if (claimButton && buttonOriginalSize) claimButton.Size = buttonOriginalSize;
}

// Fait respirer le bouton tant que le joueur n'a pas encaissé CLAIM_PULSE_RUNS fois.
// À appeler APRÈS la restauration de claimButton.Size dans setup(), sinon la taille
// d'origine serait écrasée par une frame de pulse.
function startClaimPulse(): void {
	if (tutorialActive) return;
	if (sessionClaimCount >= CLAIM_PULSE_RUNS) return;
	if (!claimButton || !buttonOriginalSize) return;

	// Halo créé une seule fois, en code — rien à ajouter dans Studio.
	if (!claimPulseStroke) {
		const stroke = new Instance("UIStroke");
		stroke.Name = "ClaimPulseStroke";
		stroke.Thickness = 4;
		stroke.Color = new Color3(1, 1, 1);
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		stroke.Parent = claimButton;
		claimPulseStroke = stroke;
	}
	claimPulseStroke.Enabled = true;
	claimPulseStroke.Transparency = 0.8;

	const s = buttonOriginalSize;
	const grown = new UDim2(
		s.X.Scale * CLAIM_PULSE_SCALE,
		s.X.Offset * CLAIM_PULSE_SCALE,
		s.Y.Scale * CLAIM_PULSE_SCALE,
		s.Y.Offset * CLAIM_PULSE_SCALE,
	);
	claimPulseTween = TweenService.Create(claimButton, ClaimPulseTI, { Size: grown });
	claimPulseTween.Play();
	claimPulseStrokeTween = TweenService.Create(claimPulseStroke, ClaimPulseTI, { Transparency: 0.1 });
	claimPulseStrokeTween.Play();
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(inGameUI: ScreenGui): void {
	const popup = inGameUI.WaitForChild("RocketLaunch") as Frame;
	const claimButtonFrame = popup.WaitForChild("ClaimButtonFrame") as Frame;
	claimButton = claimButtonFrame.WaitForChild("ClaimButton") as TextButton;
	claimGradient = claimButton.WaitForChild("UIGradientClaim") as UIGradient;
	homeGradient = claimButton.WaitForChild("UIGradientHome") as UIGradient;
	claimLabel = claimButtonFrame.WaitForChild("TextLabel") as TextLabel;
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
	if (!claimLabelOriginalText) claimLabelOriginalText = claimLabel.Text; // "Claim"
	if (!claimButtonOriginalColor) claimButtonOriginalColor = claimButton.BackgroundColor3;
	if (!multiplierTextOriginalSize) multiplierTextOriginalSize = multiplierText.TextSize;

	// Reset per-game state
	baseFov = Workspace.CurrentCamera?.FieldOfView ?? 70;
	isGameActive = true;
	hasClaimed = false;
	perfectClaimPending = false;
	isGoHomeMode = false;
	runId += 1; // invalide un réarmement "Go Home" encore en attente d'une partie précédente
	claimLabel.Text = claimLabelOriginalText; // le bouton repart en "Claim"
	// EffectiveBaseCash (attribut répliqué) : base du gain affiché dans ResultMultiplierText.
	// Lu une fois par partie — comme côté serveur, il ne bouge pas en cours de hold.
	// Mega Rocket : le serveur applique le même ×8 au base cash du vol, l'aperçu doit
	// donc le refléter (shared/MegaRocketConfig).
	resultBaseCash =
		((Players.LocalPlayer.GetAttribute("EffectiveBaseCash") as number | undefined) ?? 100) *
		(hasMegaRocket(Players.LocalPlayer) ? MEGA_ROCKET_BASE_CASH_MULT : 1);
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
	InformationText.setInFlight(true); // les bandeaux descendent sous le MultiplierText
	MusicController.startRun(); // début du hold → la BGM de base continue de jouer
	ButtonAnimations.playHold(); // remplace la pose "interact" : le perso appuie et reste sur le bouton
	RocketSteerController.start(); // le mouvement natif gauche/droite pilote la fusée pendant le vol
	multiplierText.TextSize = multiplierTextOriginalSize;
	multiplierText.TextColor3 = MULTIPLIER_COLOR_START; // chaque décollage repart du rouge clair
	multiplierTextSize = multiplierTextOriginalSize;
	multiplierHeat = 0;
	multiplierColorLocked = false; // le verrou de couleur ne vaut que pour un vol
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
	// Décollage : le bouton repart avec le dégradé "Claim" (le dégradé "Home" ne réapparaîtra
	// qu'au réarmement Go Home).
	if (claimGradient) claimGradient.Enabled = true;
	if (homeGradient) homeGradient.Enabled = false;

	// Onboarding : le bouton respire tant que le joueur n'a pas encaissé quelques fois.
	// Doit venir APRÈS la restauration de Size ci-dessus.
	stopClaimPulse();
	startClaimPulse();

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
	activatedConn?.Disconnect();

	// Claim : le joueur VERROUILLE son multiplicateur. La partie NE s'arrête PAS —
	// la fusée continue de monter (le multiplierText grimpe encore) jusqu'à l'explosion.
	// Le bouton devient rouge (comme à l'explosion) et non-cliquable (pas de double claim) ;
	// on joue le son de cash ; le serveur renvoie la valeur verrouillée exacte via
	// ClaimAcceptedEvent (figée dans ResultMultiplierText).
	const fireClaim = () => {
		if (!isGameActive || hasClaimed) return;
		hasClaimed = true;
		sessionClaimCount += 1;
		stopClaimPulse();
		if (claimButton) {
			claimButton.Active = false;
			claimButton.Interactable = false;
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR;
		}
		playClaimCashSound();
		Events.ClaimButtonEvent.FireServer();

		// Le bouton se réarme après CLAIM_REARM_DELAY, cette fois en "Go Home" : le gain
		// est verrouillé, le joueur peut rentrer à la base au lieu d'attendre l'explosion.
		// Annulé si la partie s'est terminée entre-temps (explosion) ou si une nouvelle
		// partie a démarré (runId).
		// PAS pendant le tutorial : le step claim-explode veut MONTRER l'explosion, et un
		// bouton "Go Home" rallumé (mais bloqué par TutorialGate) ne ferait qu'inviter à un
		// clic sans effet. Le bouton reste donc éteint, tel que le claim l'a laissé.
		if (tutorialActive) return;
		const myRun = runId;
		task.delay(CLAIM_REARM_DELAY, () => {
			if (myRun !== runId || !isGameActive || !claimButton) return;
			isGoHomeMode = true;
			if (claimLabel) claimLabel.Text = GO_HOME_LABEL;
			// Retour à la couleur d'origine : le rouge signale "non cliquable", or le
			// bouton redevient bien cliquable (cette fois pour rentrer à la base). C'est à
			// cet instant précis — pas pendant l'assombrissement du claim — qu'on bascule
			// du dégradé "Claim" vers le dégradé "Home".
			if (claimButtonOriginalColor) claimButton.BackgroundColor3 = claimButtonOriginalColor;
			if (claimGradient) claimGradient.Enabled = false;
			if (homeGradient) homeGradient.Enabled = true;
			claimButton.Active = true;
			claimButton.Interactable = true;
		});
	};

	// Retour à la base : la fusée s'arrête et la caméra revient au joueur, exactement
	// comme après une explosion — c'est le serveur qui clôt la partie (GameResultEvent
	// avec exploded=false → CameraController.BringBackPlayerCamera).
	const fireGoHome = () => {
		if (!isGameActive || !isGoHomeMode) return;
		isGoHomeMode = false;
		stopClaimPulse();
		if (claimButton) {
			claimButton.Active = false;
			claimButton.Interactable = false;
			claimButton.BackgroundColor3 = CLAIM_BUTTON_EXPLODE_COLOR; // fini : bouton éteint
		}
		MusicController.stopRunMusic(); // fin du vol : on coupe la musique du run tout de suite
		RocketSteerController.stop(); // plus de pilotage dès le clic
		// On coupe TOUS les effets de vol d'un coup : tremblement de caméra, bloom et FOV.
		// Indispensable ici : la boucle RenderStepped qui atténue le tremblement ne tourne
		// que tant que la partie est active, donc un reste de shake serait figé sur la
		// caméra une fois rendue au joueur (l'explosion, elle, a sa propre extinction).
		resetPostProcess(true);
		Events.GoHomeEvent.FireServer();
	};

	activatedConn = claimButton.Activated.Connect(() => {
		if (isGoHomeMode) fireGoHome();
		else fireClaim();
	});
}
