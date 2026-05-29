import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";
import { ReplicatedStorage, TweenService, Workspace } from "@rbxts/services";
import { invincible } from "server/modules/CheatConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";
import { ConfettiBurst } from "server/modules/ConfettiBurst";
import { STAGE_TIMING_CONFIGS, TOTAL_STAGE_DURATION } from "shared/ButtonGameConfig";

// ── Game tuning ───────────────────────────────────────────────────────────────

// Default multiplicator increments — used when a button attribute is missing.
// The actual values come from the button's Level1..Level5 attributes.
const DEFAULT_MULTIPLIERS: [number, number, number, number, number] = [1, 2, 5, 8, 15];

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
const EXPLOSION_KILL_PRESSURE = 180000;
const EXPLOSION_SOUND_ID = "rbxassetid://139771888058836";
const EXPLOSION_SOUND_VOLUME = 0.8;
const EXPLOSION_SOUND_ROLLOFF = 120;

// Alias — keeps the rest of the file unchanged while sourcing the value from the shared config
const TOTAL_DURATION = TOTAL_STAGE_DURATION;

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

// Triggers a 3D explosion at `pos`: visual and sound fire together from the
// same replication batch, so clients see and hear them simultaneously.
// blastPressure = 0 for parry (visual-only), non-zero for lethal explosions.
//
// BlastRadius is intentionally tight (EXPLOSION_BLAST_RADIUS): the radius
// gates *both* visual size and the BlastPressure reach. Keeping it small means
// the fling is naturally scoped to the player anchored on top of the button —
// bystanders standing a few studs away aren't inside the bubble and are left
// alone, no manual filtering required.
function triggerExplosionAt(pos: Vector3, blastPressure: number): void {
	// Sound cloned from the pre-buffered template — no CDN fetch on the client.
	// Parented to Terrain via an Attachment for proper 3D rolloff.
	const attachment = new Instance("Attachment");
	attachment.Parent = Workspace.Terrain;
	attachment.WorldPosition = pos;

	const sound = explosionSoundTemplate.Clone();
	sound.Parent = attachment;
	sound.Play();
	sound.Ended.Connect(() => attachment.Destroy());

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
	const { baseCash } = session;
	let currentMultiplier = 0;
	let isActive = true;

	// ── Read per-button multiplier increments from attributes (Level1..Level5) ─────
	// Attributes sit on the Model (Workspace → Buttons → Model), not on the Part itself.
	// Same cast pattern as ButtonModule.ts for BaseCash — already validated in-codebase.
	const buttonModel = session.proximityPrompt.FindFirstAncestorWhichIsA("Model");
	const getLevel = (i: number): number =>
		(buttonModel?.GetAttribute(`Level${i + 1}`) as number | undefined) ?? DEFAULT_MULTIPLIERS[i];
	const levelValues: [number, number, number, number, number] = [
		getLevel(0),
		getLevel(1),
		getLevel(2),
		getLevel(3),
		getLevel(4),
	];

	Events.ButtonLevelsEvent.FireClient(
		player,
		levelValues[0],
		levelValues[1],
		levelValues[2],
		levelValues[3],
		levelValues[4],
	);

	Events.BaseCashEvent.FireClient(player, baseCash);
	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
	Events.RiskUpdateEvent.FireClient(player, 0);

	const releaseConn = Events.ReleaseButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive) return;
		isActive = false;
		releaseConn.Disconnect();

		const earned = baseCash * currentMultiplier;
		Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
		ConfettiBurst.play(buttonModel);
		EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
	});

	// ── Boucle multiplier ─────────────────────────────────────────────────────
	// Tourne à sa propre fréquence (tickInterval), totalement indépendante du
	// TICK_RATE. Chaque tick attend exactement tickInterval secondes — pas de
	// rattrapage en lot possible.
	task.spawn(() => {
		const lastIndex = STAGE_TIMING_CONFIGS.size() - 1;
		let stageIndex = 0;
		let timeInStage = 0;

		while (isActive) {
			const stageTiming = STAGE_TIMING_CONFIGS[stageIndex];

			task.wait(stageTiming.tickInterval);
			if (!isActive) break;

			timeInStage += stageTiming.tickInterval;
			currentMultiplier += levelValues[stageIndex];
			Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);

			// Passage au stage suivant quand la durée est écoulée
			if (stageIndex < lastIndex && timeInStage >= stageTiming.duration) {
				stageIndex++;
				timeInStage = 0;
			}
		}
	});

	// ── Boucle risque & progression ───────────────────────────────────────────
	// Tourne à TICK_RATE pour les checks d'explosion, le risque et la progress bar.
	task.spawn(() => {
		let timeHeld = 0;

		while (isActive) {
			task.wait(TICK_RATE);
			if (!isActive) break;

			timeHeld += TICK_RATE;

			const risk = getRisk(timeHeld);
			Events.RiskUpdateEvent.FireClient(player, risk);

			const progress = math.min(timeHeld / TOTAL_DURATION, 1);
			Events.ProgressUpdateEvent.FireClient(player, progress);

			if (!invincible && math.random() < risk) {
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
					const earned = baseCash * currentMultiplier;
					Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
					ConfettiBurst.play(buttonModel);
					EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
				} else {
					const character = player.Character;
					const hrp = character?.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
					const humanoid = character?.FindFirstChildOfClass("Humanoid");
					// Capture button reference before session is cleared
					const buttonPart = session.proximityPrompt.Parent as BasePart | undefined;

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

						const earned = baseCash * currentMultiplier;
						Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
						EndGameButtonModule.enter(player, "released", baseCash, currentMultiplier, earned, 1);
					} else {
						if (hrp) hrp.Anchored = false;

						if (character) {
							for (const desc of character.GetDescendants()) {
								if (desc.IsA("Motor6D")) desc.Enabled = false;
							}
						}

						if (buttonPart) triggerExplosionAt(buttonPart.Position, EXPLOSION_KILL_PRESSURE);

						if (humanoid) humanoid.Health = 0;

						Events.PlayerKilledEvent.FireClient(player);
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
