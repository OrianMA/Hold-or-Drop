import { RunService, Workspace } from "@rbxts/services";
import { Room } from "server/rooms/Room";
import {
	ROCKET_ACCEL,
	ROCKET_MAX_SPEED,
	STEER_ROT_SPEED_GROUND,
	STEER_ROT_SPEED_SPACE,
	STEER_SPACE_HEIGHT,
} from "shared/RocketGameConfig";
import { AudioConfig } from "shared/AudioConfig";

// Drives the per-room rocket (the MovableModel): it rises while the button is held
// with a slow, accelerating, real-rocket feel, lights its engine Fire (NitroParticles)
// while moving, and physically blows the rocket apart on a loss.
//
// Moving the whole MovableModel via PivotTo carries its CameraPosPart /
// CameraParentPart up with it, so the client's orbit camera (which reads the pivot
// live) follows the rocket automatically — see CameraController.StartOrbit.

const EXPLOSION_EMITTER = "ExplosionParticles";
const PARTICLES_PARENT = "ParticlesParentPart";
const EXPLOSION_PARTICLE_COUNT = 60;
// Part(s) inside the rocket holding the engine emitter(s) — lit while the rocket moves.
// A rocket can carry several NitroParticles parts (multi-engine rockets), each with one
// or more Fire/ParticleEmitter/Smoke. Shared with RocketPlacer (engine off at rest).
export const NITRO_PART = "NitroParticles";
// 3D rolloff (studs) for the looped launch roar, server-authored like the explosion boom.
const LAUNCH_SOUND_ROLLOFF = 150;
// The rocket body model inside the MovableModel — these are the parts that physically
// break apart on an explosion (the Camera*/Particles helper parts stay anchored so the
// orbit camera keeps holding on the blast site). The actual rocket is instantiated by
// RocketPlacer from ReplicatedStorage/RocketModels (level chosen by rebirth) and always
// renamed to this stable name, so the launcher finds it regardless of which level it is.
export const ROCKET_MODEL = "Rocket";

// ── Physical explosion tuning ───────────────────────────────────────────────────
// Height-based gravity (world-space Y, studs): above SPACE_HEIGHT the debris is in
// space and weightless; through the SPACE_HEIGHT→GROUND_HEIGHT band gravity fades in;
// below GROUND_HEIGHT it falls under full earth gravity.
const SPACE_HEIGHT = 95;
const GROUND_HEIGHT = 50;
// Outward burst applied to every debris part the instant the rocket bursts apart.
// The radial spread is horizontal-only and the vertical kick scales with the part's
// height inside the rocket, so every part is flung UP (never any -Y velocity): the
// nose is launched hardest, the lowest parts barely lift.
const BURST_SPEED = 45; // base horizontal radial speed (studs/s)
const BURST_SPEED_VARIANCE = 25; // added 0..n at random per part
const BURST_UP_MIN = 5; // upward kick for the lowest part (barely lifts, never -Y)
const BURST_UP_MAX = 95; // upward kick for the highest part (nose flung hardest)
const BURST_SPIN = 18; // random angular velocity magnitude (rad/s)

// One rocket body part with the data needed to fully restore it after a physical
// explosion: its pose relative to the launch pad and its authored collision flag.
interface RocketPart {
	part: BasePart;
	offset: CFrame; // CFrame relative to the launch-pad pivot
	canCollide: boolean; // authored CanCollide, restored on reset
}

interface RocketState {
	conn: RBXScriptConnection;
	velocity: number;
	// Vol gelé sur place (tutorial) : la boucle d'ascension ne bouge plus mais la
	// vélocité acquise est CONSERVÉE pour la reprise. getVelocity renvoie 0 pendant
	// le gel, donc le multiplicateur du jeu se fige aussi — c'est voulu.
	paused: boolean;
	// Player's current left/right steering intent: -1 (left) / 0 / +1 (right). Set by
	// setSteer from the client's native movement input; released (0) leaves the tilt as-is.
	steer: number;
	// Current roll angle (radians), integrated from `steer` with NO cap (rolls freely).
	// Kept across frames (no auto-centre) — the rocket holds whatever tilt it was left at.
	tilt: number;
	// Upright launch pose (the pad pivot). Steering rolls relative to this, and the
	// running climb position is measured from it.
	basePivot: CFrame;
	// Running world position of the pivot as it climbs along its (possibly tilted) up-axis.
	pos: Vector3;
}

const states = new Map<Room, RocketState>();
// The authored launch-pad pivot, captured once per room so every launch resets to
// the exact same spot regardless of where a previous run left the model.
const originalPivots = new Map<Room, CFrame>();
// The rocket-body parts (RocketLvl1 descendants) with their pad-relative pose,
// captured once per room so a physical explosion can be fully undone on reset.
const rocketParts = new Map<Room, RocketPart[]>();
// The active debris-physics Heartbeat while the rocket is mid-explosion.
const debrisConns = new Map<Room, RBXScriptConnection>();
// The looped 3D "engine roar" sound per room, created once and parented to the rocket
// engine so it rises with the rocket. Played on launch, stopped on every ending (stopRoom).
const launchSounds = new Map<Room, Sound>();

function getRocketModel(room: Room): Model | undefined {
	return room.movableModel.FindFirstChild(ROCKET_MODEL) as Model | undefined;
}

// The engine part (holds the nitro Fire) — the natural 3D source for the launch roar.
function getNitroPart(room: Room): BasePart | undefined {
	const nitro = getRocketModel(room)?.FindFirstChild(NITRO_PART, true);
	return nitro && nitro.IsA("BasePart") ? nitro : undefined;
}

// Lazily create + cache the looped launch sound, parented to the engine part so the roar
// emanates from the rocket and follows it up (the whole MovableModel moves during ascent).
// 3D positional like the explosion boom — server-authored so every nearby client hears it.
function getLaunchSound(room: Room): Sound | undefined {
	const existing = launchSounds.get(room);
	if (existing && existing.Parent) return existing;

	const host = getNitroPart(room) ?? room.movableModel.FindFirstChildWhichIsA("BasePart", true);
	if (!host) return undefined;

	const sound = new Instance("Sound");
	sound.Name = "RocketLaunchSound";
	sound.SoundId = AudioConfig.sfx.rocketLaunch.id;
	sound.Volume = AudioConfig.sfx.rocketLaunch.volume;
	sound.Looped = true;
	sound.RollOffMaxDistance = LAUNCH_SOUND_ROLLOFF;
	sound.Parent = host;
	launchSounds.set(room, sound);
	return sound;
}

// Capture the rocket body parts and their pad-relative pose once per room. Must be
// called while the model sits on its launch pad (so the captured offsets are the
// on-pad arrangement we restore to).
function captureRocketParts(room: Room): void {
	if (rocketParts.has(room)) return;
	const model = getRocketModel(room);
	if (!model) return;
	const padPivot = originalPivots.get(room) ?? room.movableModel.GetPivot();
	const parts: RocketPart[] = [];
	for (const d of model.GetDescendants()) {
		if (d.IsA("BasePart")) {
			parts.push({ part: d, offset: padPivot.ToObjectSpace(d.CFrame), canCollide: d.CanCollide });
			// The follow camera's subject is the rocket, so its occlusion raycasts would
			// hit the rocket body and pull the camera in. CanQuery = false excludes the
			// body from those raycasts (physics/collisions untouched) so the camera never
			// "collides" with the rocket.
			d.CanQuery = false;
		}
	}
	rocketParts.set(room, parts);
}

// Re-anchor and re-pose any exploded debris back onto the pad, restoring authored
// collision and zeroing physics — leaves the rocket ready for the next launch.
function restoreRocketParts(room: Room): void {
	const conn = debrisConns.get(room);
	if (conn) {
		conn.Disconnect();
		debrisConns.delete(room);
	}

	const parts = rocketParts.get(room);
	const padPivot = originalPivots.get(room);
	if (!parts || !padPivot) return;

	for (const rp of parts) {
		const part = rp.part;
		if (!part.Parent) continue;
		part.AssemblyLinearVelocity = new Vector3(0, 0, 0);
		part.AssemblyAngularVelocity = new Vector3(0, 0, 0);
		part.Anchored = true;
		part.CanCollide = rp.canCollide;
		part.CFrame = padPivot.mul(rp.offset);
	}
}

// Light/extinguish every engine emitter (Fire/ParticleEmitter/Smoke) inside the rocket's
// NitroParticles part(s). Rockets can have several NitroParticles parts (multi-engine), so
// we toggle them all — iterating the whole MovableModel catches every one.
function setNitroEnabled(room: Room, enabled: boolean): void {
	for (const d of room.movableModel.GetDescendants()) {
		if (
			(d.IsA("Fire") || d.IsA("ParticleEmitter") || d.IsA("Smoke")) &&
			d.FindFirstAncestor(NITRO_PART) !== undefined
		) {
			d.Enabled = enabled;
		}
	}
}

function stopRoom(room: Room): void {
	const state = states.get(room);
	if (state) {
		state.conn.Disconnect();
		states.delete(room);
	}
	setNitroEnabled(room, false); // moteur éteint dès que la fusée ne bouge plus
	// Coupe le son de décollage sur toute fin de partie (explosion, claim/release, quit)
	// — stopRoom est le point de passage commun à stop/reset/explode.
	const sound = launchSounds.get(room);
	if (sound) sound.Stop();
}

function resetRoom(room: Room): void {
	stopRoom(room);
	restoreRocketParts(room); // re-anchor + re-pose any exploded debris before snapping back
	const pivot = originalPivots.get(room);
	if (pivot) room.movableModel.PivotTo(pivot);
}

export const RocketLauncher = {
	// Start the ascent: velocity ramps from 0 to ROCKET_MAX_SPEED, accelerating by
	// ROCKET_ACCEL. `speedFactor` scales both — it is the player's Rocket Speed stat
	// value (1 = crawling, higher = faster), so the rocket and the velocity-driven
	// payout multiplier speed up together.
	launch(room: Room, speedFactor = 1): void {
		if (!originalPivots.has(room)) originalPivots.set(room, room.movableModel.GetPivot());
		resetRoom(room); // start clean from the pad (restores debris from a prior explosion)
		captureRocketParts(room); // capture the on-pad rocket pose once, now that we're at the pad

		const maxSpeed = ROCKET_MAX_SPEED * speedFactor;
		const accel = ROCKET_ACCEL * speedFactor;

		// Steering rolls the rocket relative to this upright pad pose; the climb position
		// starts here and integrates along the rocket's own (tilted) up-axis each frame.
		const basePivot = originalPivots.get(room) ?? room.movableModel.GetPivot();
		const state: RocketState = {
			conn: undefined!,
			velocity: 0,
			paused: false,
			steer: 0,
			tilt: 0,
			basePivot,
			pos: basePivot.Position,
		};
		state.conn = RunService.Heartbeat.Connect((dt) => {
			if (state.paused) return; // vol gelé : on ne touche ni à la vélocité ni au pivot
			state.velocity = math.min(state.velocity + accel * dt, maxSpeed);

			// Roll authority ramps with altitude: near-zero at the pad (STEER_ROT_SPEED_GROUND),
			// full once the rocket reaches space (STEER_ROT_SPEED_SPACE at STEER_SPACE_HEIGHT).
			const altitude = state.pos.Y - state.basePivot.Position.Y;
			const authority = math.clamp(altitude / STEER_SPACE_HEIGHT, 0, 1);
			const rotSpeed = STEER_ROT_SPEED_GROUND + (STEER_ROT_SPEED_SPACE - STEER_ROT_SPEED_GROUND) * authority;

			// Integrate the roll toward the held direction — NO cap, it rolls freely.
			// `steer = 0` (released) leaves the tilt untouched; the gradual integration is
			// what makes it read as a smooth tween rather than a brute snap.
			state.tilt += state.steer * rotSpeed * dt;

			// Move along the rocket's OWN up-axis (rolled by `tilt` about its forward axis),
			// so a roll makes it drift sideways instead of straight up. The `-tilt` inverts
			// the steering direction (left input leans right and vice-versa, as requested).
			const orientation = state.basePivot.Rotation.mul(CFrame.Angles(0, 0, -state.tilt));
			state.pos = state.pos.add(orientation.UpVector.mul(state.velocity * dt));
			room.movableModel.PivotTo(orientation.add(state.pos));
		});
		states.set(room, state);

		setNitroEnabled(room, true); // moteur allumé tant que la fusée monte
		const sound = getLaunchSound(room);
		if (sound) sound.Play(); // son de décollage en boucle (3D, suit la fusée)
	},

	// Current ascent velocity (studs/s) for a room, or 0 if not flying / gelé. Read by
	// the game loop's multiplier tick so the payout multiplier tracks the rocket's speed
	// — un vol gelé ne fait donc pas grimper le multiplicateur.
	getVelocity(room: Room): number {
		const state = states.get(room);
		if (!state || state.paused) return 0;
		return state.velocity;
	},

	// Set the player's left/right steering intent for a flying rocket: dir < 0 = left,
	// dir > 0 = right, 0 = released (hold current tilt). No-op when the room isn't
	// flying (no active state), so stale input outside a run is harmless. The roll is
	// integrated in the ascent loop (altitude-scaled rate) — this only records direction.
	setSteer(room: Room, dir: number): void {
		const state = states.get(room);
		if (!state) return;
		state.steer = dir > 0 ? 1 : dir < 0 ? -1 : 0;
	},

	// Gèle le vol sur place : moteur éteint, roar en pause, plus aucun déplacement — la
	// vélocité acquise est gardée pour unfreeze. Utilisé par la mise en scène du tutorial
	// (aucun autre appelant). No-op si la room ne vole pas.
	freeze(room: Room): void {
		const state = states.get(room);
		if (!state || state.paused) return;
		state.paused = true;
		setNitroEnabled(room, false);
		const sound = launchSounds.get(room);
		if (sound) sound.Pause();
	},

	// Reprend un vol gelé à la vélocité qu'il avait.
	unfreeze(room: Room): void {
		const state = states.get(room);
		if (!state || !state.paused) return;
		state.paused = false;
		setNitroEnabled(room, true);
		const sound = launchSounds.get(room);
		if (sound) sound.Resume();
	},

	isFrozen(room: Room): boolean {
		return states.get(room)?.paused === true;
	},

	// Stop the ascent in place (no reset) — used on a win/release.
	stop(room: Room): void {
		stopRoom(room);
	},

	// Stop and snap the rocket back to its launch pad, ready for the next run.
	reset(room: Room): void {
		resetRoom(room);
	},

	// Drop every cache tied to the room's current rocket instance. RocketPlacer calls
	// this whenever it (re)places the rocket — rooms are reused across occupants, so the
	// cached body parts / pad pivot would otherwise point at a destroyed model and the
	// next launch would operate on stale instances. Cleared here, they are recaptured
	// fresh on the following launch (from the new rocket sitting on the pad).
	clearRocketCache(room: Room): void {
		stopRoom(room); // disconnect any active ascent + stop the looped roar
		const dconn = debrisConns.get(room);
		if (dconn) {
			dconn.Disconnect();
			debrisConns.delete(room);
		}
		rocketParts.delete(room);
		originalPivots.delete(room);
		launchSounds.delete(room); // the old sound lived on the destroyed rocket; recreate next launch
	},

	// Physical rocket explosion: burst the ExplosionParticles emitter, then unanchor
	// every rocket body part and blow them outward so the rocket visibly breaks apart.
	// The debris keeps the rocket's upward ascent momentum (so the rocket "continues to
	// go up" after it explodes), then a Heartbeat applies height-based gravity (weightless
	// in space above SPACE_HEIGHT, full earth gravity below GROUND_HEIGHT) that bleeds that
	// momentum off and pulls it back down. Undone by reset() (§6.17).
	explode(room: Room): void {
		// Inherit the rocket's current ascent speed before halting the ascent loop, so the
		// debris keeps rising instead of stopping dead the instant it explodes.
		const ascentVelocity = states.get(room)?.velocity ?? 0;
		stopRoom(room); // stop the PivotTo ascent + kill the engine fire — debris physics takes over

		// Particle burst (existing visual cue).
		const ppp = room.movableModel.FindFirstChild(PARTICLES_PARENT);
		const emitter = ppp?.FindFirstChild(EXPLOSION_EMITTER);
		if (emitter && emitter.IsA("ParticleEmitter")) emitter.Emit(EXPLOSION_PARTICLE_COUNT);

		const parts = rocketParts.get(room);
		if (!parts || parts.size() === 0) return;

		const model = getRocketModel(room);
		const center = (model ?? room.movableModel).GetPivot().Position;
		const gravity = Workspace.Gravity;

		// Vertical extent of the rocket so the upward kick can scale by height: the
		// lowest part lifts by BURST_UP_MIN, the nose by BURST_UP_MAX. No part ever
		// gets a downward (-Y) velocity.
		let minY = math.huge;
		let maxY = -math.huge;
		for (const rp of parts) {
			const y = rp.part.Position.Y;
			if (y < minY) minY = y;
			if (y > maxY) maxY = y;
		}
		const span = math.max(maxY - minY, 0.05);

		// Unanchor each body part and fling it outward: horizontal-only radial spread
		// (so the burst never pushes anything down) plus a height-scaled upward kick and
		// random spin, so the rocket reads as blown apart and launched up. Debris is
		// non-collidable while flying so it can't snag on room geometry or jitter.
		for (const rp of parts) {
			const part = rp.part;
			if (!part.Parent) continue;
			part.Anchored = false;
			part.CanCollide = false;

			const away = part.Position.sub(center);
			const flat = new Vector3(away.X, 0, away.Z); // radial spread, horizontal only
			const dir =
				flat.Magnitude > 0.05 ? flat.Unit : new Vector3(math.random() * 2 - 1, 0, math.random() * 2 - 1).Unit;
			const speed = BURST_SPEED + math.random() * BURST_SPEED_VARIANCE;
			const heightFactor = (part.Position.Y - minY) / span; // 0 = lowest, 1 = nose
			const up = BURST_UP_MIN + heightFactor * (BURST_UP_MAX - BURST_UP_MIN);
			part.AssemblyLinearVelocity = dir.mul(speed).add(new Vector3(0, up, 0));
			// Radial burst + an upward kick + the inherited ascent momentum → the rocket
			// keeps climbing as it breaks apart, until height-based gravity pulls it back.
			// part.AssemblyLinearVelocity = dir.mul(speed).add(new Vector3(0, BURST_UP_BIAS + ascentVelocity, 0));
			part.AssemblyAngularVelocity = new Vector3(
				(math.random() * 2 - 1) * BURST_SPIN,
				(math.random() * 2 - 1) * BURST_SPIN,
				(math.random() * 2 - 1) * BURST_SPIN,
			);
		}

		// Height-based gravity. Roblox already pulls `gravity` studs/s² down on every
		// unanchored part; each frame we add back `gravity*(1-scale)` upward so the net
		// downward pull is `gravity*scale`: scale 0 above SPACE_HEIGHT (weightless space),
		// ramping to 1 at GROUND_HEIGHT and staying 1 below (full earth gravity).
		const conn = RunService.Heartbeat.Connect((dt) => {
			for (const rp of parts) {
				const part = rp.part;
				if (!part.Parent || part.Anchored) continue;
				const y = part.Position.Y;
				let scale: number;
				if (y >= SPACE_HEIGHT) scale = 0;
				else if (y <= GROUND_HEIGHT) scale = 1;
				else scale = (SPACE_HEIGHT - y) / (SPACE_HEIGHT - GROUND_HEIGHT);
				const cancel = gravity * (1 - scale) * dt;
				if (cancel > 0) {
					part.AssemblyLinearVelocity = part.AssemblyLinearVelocity.add(new Vector3(0, cancel, 0));
				}
			}
		});
		debrisConns.set(room, conn);
	},
};
