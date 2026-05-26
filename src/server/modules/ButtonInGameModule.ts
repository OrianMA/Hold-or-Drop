import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";
import { ReplicatedStorage, TweenService, Workspace } from "@rbxts/services";

// ── Game tuning ───────────────────────────────────────────────────────────────

interface MultiplierStage {
	multiplicatorAdded: number;
	duration: number;
}

const MULTIPLIER_STAGES: MultiplierStage[] = [
	{ multiplicatorAdded: 1, duration: 5 },
	{ multiplicatorAdded: 2, duration: 4 },
	{ multiplicatorAdded: 5, duration: 3 },
	{ multiplicatorAdded: 8, duration: 3 },
	{ multiplicatorAdded: 15, duration: 3 }, // last stage — runs forever
];

const MAX_RISK = 0.8;
const TICK_RATE = 0.5;
const LOOSE_WIN_MULTIPLIER = 0.3;

const KNOCKBACK_DISTANCE = 15;
const KNOCKBACK_DURATION = 0.5;

const EXPLOSION_BLAST_RADIUS = 32;
const EXPLOSION_SOUND_ID = "rbxassetid://139771888058836";
const EXPLOSION_SOUND_VOLUME = 0.8;
const EXPLOSION_SOUND_ROLLOFF = 120;

// Sum of all finite stage durations — defines the full length of the risk curve
let TOTAL_DURATION = 0;
for (const stage of MULTIPLIER_STAGES) {
	TOTAL_DURATION += stage.duration;
}

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

// Single exit point for all outcomes: release, explosion, and quit from ButtonMenu
export function endButtonGame(player: Player): void {
	ButtonSessionService.cleanup(player);
	UiService.HideCurrent(player);
}

export function startButtonGame(player: Player, session: ButtonSession): void {
	const { baseCash } = session;
	let currentMultiplier = 1;
	let isActive = true;

	Events.BaseCashEvent.FireClient(player, baseCash);
	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
	Events.RiskUpdateEvent.FireClient(player, 0);

	const releaseConn = Events.ReleaseButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive) return;
		isActive = false;
		releaseConn.Disconnect();

		const earned = baseCash * currentMultiplier;
		Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
		endButtonGame(player);
	});

	task.spawn(() => {
		const lastIndex = MULTIPLIER_STAGES.size() - 1;
		let stageIndex = 0;
		let timeHeld = 0;

		while (isActive) {
			const stage = MULTIPLIER_STAGES[stageIndex];
			const isLastStage = stageIndex === lastIndex;

			let timeInStage = 0;
			let nextMultiplierTick = 1;
			let advanceStage = false;

			while (isActive) {
				task.wait(TICK_RATE);
				if (!isActive) break;

				timeInStage += TICK_RATE;
				timeHeld += TICK_RATE;

				// +multiplicatorAdded to the multiplier once per elapsed second
				while (timeInStage >= nextMultiplierTick) {
					currentMultiplier += stage.multiplicatorAdded;
					Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
					nextMultiplierTick++;
				}

				const risk = getRisk(timeHeld);
				Events.RiskUpdateEvent.FireClient(player, risk);

				const progress = math.min(timeHeld / TOTAL_DURATION, 1);
				Events.ProgressUpdateEvent.FireClient(player, progress);

				if (math.random() < risk) {
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
						endButtonGame(player);
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
							UiService.HideCurrent(player);
						} else {
							if (hrp) hrp.Anchored = false;

							if (character) {
								for (const desc of character.GetDescendants()) {
									if (desc.IsA("Motor6D")) desc.Enabled = false;
								}
							}

							if (buttonPart) triggerExplosionAt(buttonPart.Position, 180000);

							if (humanoid) humanoid.Health = 0;

							Events.PlayerKilledEvent.FireClient(player);
							const earned = math.floor(baseCash * currentMultiplier * LOOSE_WIN_MULTIPLIER);
							Events.GameResultEvent.FireClient(player, true, earned, currentMultiplier);
							UiService.HideCurrent(player);
						}
					}
					return;
				}

				if (!isLastStage && timeInStage >= stage.duration) {
					advanceStage = true;
					break;
				}
			}

			if (!advanceStage) break;
			stageIndex++;
		}
	});
}
