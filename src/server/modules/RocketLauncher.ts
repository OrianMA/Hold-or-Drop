import { RunService, Workspace } from "@rbxts/services";
import { Room } from "server/rooms/Room";
import { ROCKET_ACCEL, ROCKET_MAX_SPEED } from "shared/RocketGameConfig";

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
// Part inside the rocket holding the engine Fire(s) — lit while the rocket moves.
const NITRO_PART = "NitroParticles";
// The rocket body model inside the MovableModel — these are the parts that physically
// break apart on an explosion (the Camera*/Particles helper parts stay anchored so the
// orbit camera keeps holding on the blast site).
const ROCKET_MODEL = "RocketLvl1";

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

function getRocketModel(room: Room): Model | undefined {
	return room.movableModel.FindFirstChild(ROCKET_MODEL) as Model | undefined;
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

// Light/extinguish the engine Fire(s) inside the rocket's NitroParticles part(s).
function setNitroEnabled(room: Room, enabled: boolean): void {
	for (const d of room.movableModel.GetDescendants()) {
		if (d.IsA("Fire") && d.FindFirstAncestor(NITRO_PART) !== undefined) d.Enabled = enabled;
	}
}

function stopRoom(room: Room): void {
	const state = states.get(room);
	if (state) {
		state.conn.Disconnect();
		states.delete(room);
	}
	setNitroEnabled(room, false); // moteur éteint dès que la fusée ne bouge plus
}

function resetRoom(room: Room): void {
	stopRoom(room);
	restoreRocketParts(room); // re-anchor + re-pose any exploded debris before snapping back
	const pivot = originalPivots.get(room);
	if (pivot) room.movableModel.PivotTo(pivot);
}

export const RocketLauncher = {
	// Start the ascent: velocity ramps from 0 to ROCKET_MAX_SPEED, accelerating by
	// ROCKET_ACCEL. `speedFactor` scales both (1 = neutral) — it will later be fed
	// from the player's multiplier level.
	launch(room: Room, speedFactor = 1): void {
		if (!originalPivots.has(room)) originalPivots.set(room, room.movableModel.GetPivot());
		resetRoom(room); // start clean from the pad (restores debris from a prior explosion)
		captureRocketParts(room); // capture the on-pad rocket pose once, now that we're at the pad

		const maxSpeed = ROCKET_MAX_SPEED * speedFactor;
		const accel = ROCKET_ACCEL * speedFactor;

		const state: RocketState = { conn: undefined!, velocity: 0 };
		state.conn = RunService.Heartbeat.Connect((dt) => {
			state.velocity = math.min(state.velocity + accel * dt, maxSpeed);
			room.movableModel.PivotTo(room.movableModel.GetPivot().add(new Vector3(0, state.velocity * dt, 0)));
		});
		states.set(room, state);

		setNitroEnabled(room, true); // moteur allumé tant que la fusée monte
	},

	// Stop the ascent in place (no reset) — used on a win/release.
	stop(room: Room): void {
		stopRoom(room);
	},

	// Stop and snap the rocket back to its launch pad, ready for the next run.
	reset(room: Room): void {
		resetRoom(room);
	},

	// Physical rocket explosion: burst the ExplosionParticles emitter, then unanchor
	// every rocket body part and blow them outward so the rocket visibly breaks apart.
	// A Heartbeat applies height-based gravity to the debris (weightless in space above
	// SPACE_HEIGHT, full earth gravity below GROUND_HEIGHT). Undone by reset() (§6.17).
	explode(room: Room): void {
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
				flat.Magnitude > 0.05
					? flat.Unit
					: new Vector3(math.random() * 2 - 1, 0, math.random() * 2 - 1).Unit;
			const speed = BURST_SPEED + math.random() * BURST_SPEED_VARIANCE;
			const heightFactor = (part.Position.Y - minY) / span; // 0 = lowest, 1 = nose
			const up = BURST_UP_MIN + heightFactor * (BURST_UP_MAX - BURST_UP_MIN);
			part.AssemblyLinearVelocity = dir.mul(speed).add(new Vector3(0, up, 0));
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
