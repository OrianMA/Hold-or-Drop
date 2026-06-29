import { RunService } from "@rbxts/services";
import { Room } from "server/rooms/Room";
import { ROCKET_ACCEL, ROCKET_MAX_SPEED } from "shared/RocketGameConfig";

// Drives the per-room rocket (the MovableModel): it rises while the button is held
// with a slow, accelerating, real-rocket feel, lights its engine Fire (NitroParticles)
// while moving, and bursts an explosion on a loss.
//
// Moving the whole MovableModel via PivotTo carries its CameraPosPart /
// CameraParentPart up with it, so the client's orbit camera (which reads the pivot
// live) follows the rocket automatically — see CameraController.StartOrbit.

const EXPLOSION_EMITTER = "ExplosionParticles";
const PARTICLES_PARENT = "ParticlesParentPart";
const EXPLOSION_PARTICLE_COUNT = 60;
// Part inside the rocket holding the engine Fire(s) — lit while the rocket moves.
const NITRO_PART = "NitroParticles";

interface RocketState {
	conn: RBXScriptConnection;
	velocity: number;
}

const states = new Map<Room, RocketState>();
// The authored launch-pad pivot, captured once per room so every launch resets to
// the exact same spot regardless of where a previous run left the model.
const originalPivots = new Map<Room, CFrame>();

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
	const pivot = originalPivots.get(room);
	if (pivot) room.movableModel.PivotTo(pivot);
}

export const RocketLauncher = {
	// Start the ascent: velocity ramps from 0 to ROCKET_MAX_SPEED, accelerating by
	// ROCKET_ACCEL. `speedFactor` scales both (1 = neutral) — it will later be fed
	// from the player's multiplier level.
	launch(room: Room, speedFactor = 1): void {
		if (!originalPivots.has(room)) originalPivots.set(room, room.movableModel.GetPivot());
		resetRoom(room); // start clean from the pad

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

	// Visual rocket explosion: burst the ExplosionParticles emitter authored in the
	// MovableModel's ParticlesParentPart. Best-effort — skipped if the part is absent.
	explode(room: Room): void {
		const ppp = room.movableModel.FindFirstChild(PARTICLES_PARENT);
		const emitter = ppp?.FindFirstChild(EXPLOSION_EMITTER);
		if (emitter && emitter.IsA("ParticleEmitter")) emitter.Emit(EXPLOSION_PARTICLE_COUNT);
	},
};
