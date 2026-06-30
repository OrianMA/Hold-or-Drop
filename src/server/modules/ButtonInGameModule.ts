import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";
import { PlayerProgressionService } from "server/services/PlayerProgressionService";
import { ReplicatedStorage, TweenService, Workspace } from "@rbxts/services";
import { invincible } from "server/modules/CheatConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";
import { ConfettiBurst } from "server/modules/ConfettiBurst";
import { RocketLauncher } from "server/modules/RocketLauncher";
import {
	RISK_RAMP_DURATION,
	MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER,
	MULTIPLIER_START_INCREMENT,
	MULTIPLIER_INCREMENT_GROWTH,
	EXPLOSION_VIEW_DELAY,
} from "shared/RocketGameConfig";
import { AudioConfig } from "shared/AudioConfig";

// ── Game tuning ───────────────────────────────────────────────────────────────

const MAX_RISK = 0.8;
const TICK_RATE = 0.5;
const LOOSE_WIN_MULTIPLIER = 0.3;

const KNOCKBACK_DISTANCE = 15;
const KNOCKBACK_DURATION = 0.5;

// Small enough that bystanders standing near the button aren't in range, but
// large enough to cover the assigned player teleported just above the button.
// Roblox's default explosion handles the fling — we just keep the radius tight
// so the BlastPressure stays scoped to a single character.
const EXPLOSION_BLAST_RADIUS = 12;
const EXPLOSION_SOUND_ID = AudioConfig.sfx.explosion.id;
const EXPLOSION_SOUND_VOLUME = AudioConfig.sfx.explosion.volume;
const EXPLOSION_SOUND_ROLLOFF = 120; // détail 3D propre au serveur

// Alias — keeps the risk/progress math unchanged while sourcing the value from the shared config
const TOTAL_DURATION = RISK_RAMP_DURATION;

// ── Sound preloading ──────────────────────────────────────────────────────────
// A template Sound in ReplicatedStorage replicates to all clients on join,
// causing them to pre-buffer the audio asset before any explosion fires.
// Cloning a pre-buffered template eliminates the CDN fetch delay at runtime.

const assetsFolder = (() => {
	const existing = ReplicatedStorage.FindFirstChild("HoldOrDropAssets");
	if (existing !== undefined) return existing as Folder;
	const folder = new Instance("Folder");
	folder.Name = "HoldOrDropAssets";
	folder.Parent = ReplicatedStorage;
	return folder;
})();

const explosionSoundTemplate = (() => {
	const sound = new Instance("Sound");
	sound.Name = "ExplosionSound";
	sound.SoundId = EXPLOSION_SOUND_ID;
	sound.Volume = EXPLOSION_SOUND_VOLUME;
	sound.RollOffMaxDistance = EXPLOSION_SOUND_ROLLOFF;
	sound.Parent = assetsFolder;
	return sound;
})();

// ── Helpers ───────────────────────────────────────────────────────────────────

// EaseInQuad: risk starts near 0 and accelerates — reaches MAX_RISK at TOTAL_DURATION seconds
function getRisk(timeHeld: number): number {
	const t = math.min(timeHeld / TOTAL_DURATION, 1);
	return MAX_RISK * (t * t);
}

// ── Explosion-time preload ──────────────────────────────────────────────────────
// Safety cap on the precompute loop. Risk plateaus at MAX_RISK once timeHeld passes
// TOTAL_DURATION, so even at max safety an explosion is statistically certain within a
// few seconds — this only guards against a pathological never-ending loop.
const EXPLOSION_ROLL_CAP = 2000;

// Precompute, once at launch, the exact moment the rocket will explode by running the
// SAME per-tick risk roll the live loop used to do — but all at once, up front. This
// "loads" the explosion time so the run can fire the explosion at that precise scheduled
// moment instead of re-rolling RNG every tick and discovering it late (action/event delay).
// The probability distribution is identical to the old per-tick model, so game balance is
// unchanged. Returns the time-held (seconds, tick-aligned) at which the rocket explodes.
function rollExplosionTime(safety: number): number {
	let timeHeld = 0;
	for (let i = 0; i < EXPLOSION_ROLL_CAP; i++) {
		timeHeld += TICK_RATE;
		const risk = getRisk(timeHeld) * (1 - safety);
		if (math.random() < risk) return timeHeld;
	}
	return timeHeld;
}

// Triggers a 3D explosion at `pos`: visual and sound fire together from the
// same replication batch, so clients see and hear them simultaneously.
// blastPressure = 0 for parry (visual-only), non-zero for lethal explosions.
//
// BlastRadius is intentionally tight (EXPLOSION_BLAST_RADIUS): the radius
// gates *both* visual size and the BlastPressure reach. Keeping it small means
// the fling is naturally scoped to the player anchored on top of the button —
// bystanders standing a few studs away aren't inside the bubble and are left
// alone, no manual filtering required.
// Plays the 3D explosion boom at `pos` (heard by everyone). Cloned from the
// pre-buffered template — no CDN fetch on the client. Parented to Terrain via an
// Attachment for proper 3D rolloff.
function playExplosionSoundAt(pos: Vector3): void {
	const attachment = new Instance("Attachment");
	attachment.Parent = Workspace.Terrain;
	attachment.WorldPosition = pos;

	const sound = explosionSoundTemplate.Clone();
	sound.Parent = attachment;
	sound.Play();
	sound.Ended.Connect(() => attachment.Destroy());
}

function triggerExplosionAt(pos: Vector3, blastPressure: number): void {
	playExplosionSoundAt(pos);

	const explosion = new Instance("Explosion");
	explosion.Position = pos;
	explosion.BlastRadius = EXPLOSION_BLAST_RADIUS;
	explosion.BlastPressure = blastPressure;
	explosion.DestroyJointRadiusPercent = 0;
	explosion.Parent = Workspace;
}

// ── Public API ────────────────────────────────────────────────────────────────

// Used by the ButtonMenu Quit flow — release/explosion/parry endings transition
// through EndGameButtonModule.enter() instead, which performs the same cleanup.
export function endButtonGame(player: Player): void {
	ButtonSessionService.cleanup(player);
	UiService.HideCurrent(player);
}

export function startButtonGame(player: Player, session: ButtonSession): void {
	const room = session.room;
	const buttonModel = room.buttonModel;

	// EffectiveBaseCash already folds in every money multiplier (rebirth + money
	// game-pass tier + community), additively. Read once — held for the session so
	// a mid-run boost change can't alter an in-progress hold.
	const baseCash = PlayerProgressionService.get(player, "EffectiveBaseCash");

	// Safety (0..0.70 with the pass) scales the explosion risk down. Read once.
	const safety = PlayerProgressionService.get(player, "AdditionalSecurity");

	// Démarre à 1.00x puis grimpe de façon accélérée (très lent au début, de plus en
	// plus vite — voir RocketGameConfig). Le niveau Multiplier du joueur n'est pas
	// encore pris en compte.
	let currentMultiplier = STARTING_MULTIPLIER;
	let multiplierIncrement = MULTIPLIER_START_INCREMENT;
	let isActive = true;

	// Preload the "chance" at launch: precompute the exact instant the rocket will
	// explode (tick-aligned, same distribution as the old per-tick roll). The run then
	// fires the explosion at this scheduled moment — no per-tick RNG, no discovery delay.
	// invincible ⇒ never explodes.
	const explosionAt = invincible ? math.huge : rollExplosionTime(safety);

	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
	Events.RiskUpdateEvent.FireClient(player, 0);

	// La fusée décolle dès le début du gameplay. speedFactor = 1 pour l'instant ;
	// il sera dérivé du multiplier level plus tard.
	RocketLauncher.launch(room);

	const releaseConn = Events.ReleaseButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive) return;
		isActive = false;
		releaseConn.Disconnect();

		// Win : la fusée s'arrête et revient au pad pour la prochaine partie.
		RocketLauncher.reset(room);

		const earned = math.floor(baseCash * currentMultiplier);
		Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
		ConfettiBurst.play(buttonModel);
		EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
	});

	// ── Boucle multiplier ─────────────────────────────────────────────────────
	// Croissance accélérée : chaque tick on ajoute `multiplierIncrement`, et cet
	// incrément grossit lui-même à chaque tick → très lent au début, de plus en plus
	// rapide. Indépendant de la boucle risque.
	task.spawn(() => {
		while (isActive) {
			task.wait(MULTIPLIER_TICK_RATE);
			if (!isActive) break;

			currentMultiplier += multiplierIncrement;
			multiplierIncrement += MULTIPLIER_INCREMENT_GROWTH;
			Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
		}
	});

	// ── Boucle risque / explosion planifiée ──────────────────────────────────────
	// Rafraîchit la barre de risque à TICK_RATE et déclenche l'explosion à l'instant
	// `explosionAt` précalculé au décollage — plus aucun tirage aléatoire par tick.
	task.spawn(() => {
		let timeHeld = 0;

		while (isActive) {
			// Avance jusqu'au prochain rafraîchissement de barre sans jamais dépasser
			// l'instant d'explosion précalculé → l'explosion tombe pile à `explosionAt`.
			const nextStep = math.min(timeHeld + TICK_RATE, explosionAt);
			task.wait(nextStep - timeHeld);
			if (!isActive) break;

			timeHeld = nextStep;

			// Safety reduces the effective risk: at 50% safety the ceiling halves.
			const risk = getRisk(timeHeld) * (1 - safety);
			Events.RiskUpdateEvent.FireClient(player, risk);

			if (!invincible && timeHeld >= explosionAt) {
				isActive = false;
				releaseConn.Disconnect();

				Events.ButtonExplodedEvent.FireClient(player);

				// 0.2s grace period — player can still release to cancel the explosion
				let cancelledByPlayer = false;
				const gracePeriodConn = Events.ReleaseButtonEvent.OnServerEvent.Connect((p) => {
					if (p !== player) return;
					cancelledByPlayer = true;
					gracePeriodConn.Disconnect();
				});

				task.wait(0.2);
				gracePeriodConn.Disconnect();

				if (cancelledByPlayer) {
					RocketLauncher.reset(room);
					const earned = math.floor(baseCash * currentMultiplier);
					Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
					ConfettiBurst.play(buttonModel);
					EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
				} else {
					const character = player.Character;
					const hrp = character?.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
					const humanoid = character?.FindFirstChildOfClass("Humanoid");
					// Capture button reference before session is cleared
					const buttonPart = room.buttonPart;

					// Deregister button immediately (avoids WaitForChild blocking the UI)
					ButtonSessionService.cleanup(player);

					// Freeze movement for the parry window
					const origWalkSpeed = humanoid?.WalkSpeed ?? 16;
					const origJumpPower = humanoid?.JumpPower ?? 50;
					const origJumpHeight = humanoid?.JumpHeight ?? 7.2;
					if (humanoid) {
						humanoid.WalkSpeed = 0;
						humanoid.JumpPower = 0;
						humanoid.JumpHeight = 0;
					}

					let isPerfectParry = false;
					const parryConn = Events.PerfectParryEvent.OnServerEvent.Connect((p: Player) => {
						if (p !== player) return;
						isPerfectParry = true;
						parryConn.Disconnect();
					});

					task.wait(0.5);
					parryConn.Disconnect();

					if (isPerfectParry) {
						RocketLauncher.reset(room);
						if (hrp) hrp.Anchored = true;

						if (buttonPart) triggerExplosionAt(buttonPart.Position, 0);

						// Trigger sparkle effect on the parrying player's client
						Events.PerfectParryEffectEvent.FireClient(player);
						ConfettiBurst.play(buttonModel);

						if (hrp && buttonPart) {
							const rawDir = new Vector3(
								hrp.Position.X - buttonPart.Position.X,
								0,
								hrp.Position.Z - buttonPart.Position.Z,
							);
							const dir = rawDir.Magnitude > 0 ? rawDir.Unit : new Vector3(0, 0, 1);
							const targetCFrame = hrp.CFrame.add(dir.mul(KNOCKBACK_DISTANCE));

							const tween = TweenService.Create(
								hrp,
								new TweenInfo(KNOCKBACK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ CFrame: targetCFrame },
							);
							tween.Play();
							task.wait(KNOCKBACK_DURATION);
						}

						if (hrp) hrp.Anchored = false;
						task.wait(0.5);

						if (humanoid) {
							humanoid.WalkSpeed = origWalkSpeed;
							humanoid.JumpPower = origJumpPower;
							humanoid.JumpHeight = origJumpHeight;
						}

						const earned = math.floor(baseCash * currentMultiplier);
						Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
						EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
					} else {
						// Perte : la FUSÉE explose, pas le joueur. Pas de fling, pas de mort.
						// explode() stoppe lui-même l'ascension après avoir capturé sa vitesse,
						// pour que les débris conservent l'élan vers le haut (la fusée continue
						// de monter en explosant) avant que la gravité ne les rattrape.
						const rocketPos = room.movableModel.GetPivot().Position;
						RocketLauncher.explode(room); // unanchor + burst, hérite de l'élan de montée
						playExplosionSoundAt(rocketPos); // boom 3D entendu par tous

						// Le joueur reste en vie : on lui rend sa mobilité (figée pendant la fenêtre).
						if (hrp) hrp.Anchored = false;
						if (humanoid) {
							humanoid.WalkSpeed = origWalkSpeed;
							humanoid.JumpPower = origJumpPower;
							humanoid.JumpHeight = origJumpHeight;
						}

						// Le client garde la caméra orbitale sur la fusée qui explose, puis revient.
						Events.PlayerKilledEvent.FireClient(player);

						// On laisse l'explosion se jouer avant de ramener la fusée + ouvrir le payout.
						task.wait(EXPLOSION_VIEW_DELAY);
						RocketLauncher.reset(room);

						const earned = math.floor(baseCash * LOOSE_WIN_MULTIPLIER * currentMultiplier);
						Events.GameResultEvent.FireClient(player, true, earned, currentMultiplier);
						EndGameButtonModule.enter(
							player,
							"killed",
							baseCash,
							currentMultiplier,
							earned,
							LOOSE_WIN_MULTIPLIER,
						);
					}
				}
				return;
			}
		}
	});
}
