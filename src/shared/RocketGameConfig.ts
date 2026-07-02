// ── Rocket gameplay tuning ──────────────────────────────────────────────────────
// Shared so server (game logic) and client (effects) agree on timing.

// Seconds over which the explosion risk ramps to its max and the progress bar
// fills. Defines the full length of the risk curve.
export const RISK_RAMP_DURATION = 17;

// Seconds between each multiplier tick.
export const MULTIPLIER_TICK_RATE = 1;

// Value the in-game multiplier starts at (1 = base payout before any growth).
export const STARTING_MULTIPLIER = 1;

// The payout multiplier tracks the rocket's LIVE velocity: each multiplier tick
// adds `velocity × MULTIPLIER_TICK_RATE × MULTIPLIER_PER_STUD` (i.e. it grows by
// the distance the rocket just climbed). Velocity starts at 0 and accelerates, so
// the multiplier is near-frozen at liftoff and ramps hard once the rocket is fast.
// A higher Rocket Speed stat raises the velocity, so it speeds up the multiplier
// and the rocket together.
export const MULTIPLIER_PER_STUD = 0.01;

// ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
// The rocket rises while the button is held: velocity starts at 0, ramps by
// ROCKET_ACCEL (studs/s²) up to ROCKET_MAX_SPEED (studs/s), then stays constant.
// These are PER ROCKET-SPEED-UNIT: launch() multiplies both by the player's Rocket
// Speed stat value. At Rocket Speed 1 the rocket crawls (accel 1 / max 10) so the
// multiplier barely moves; each upgrade adds a full unit (e.g. 6 → accel 6 / max 60).
export const ROCKET_ACCEL = 1;
export const ROCKET_MAX_SPEED = 10;

// ── Rocket steering (RocketLauncher) ────────────────────────────────────────────
// In flight the rocket moves along its OWN up-axis. The player's native left/right
// movement input (keyboard A/D, mobile thumbstick, gamepad stick — the character is
// anchored so it doesn't walk, RocketSteerController) rolls the rocket left/right,
// tilting its up-axis so it drifts sideways. The roll rate is near-zero at liftoff
// and ramps to full once the rocket reaches "space" (STEER_SPACE_HEIGHT studs above
// the pad), so it stays centred in the room shaft early and only becomes steerable in
// open sky. The roll is UNCAPPED — it accumulates freely — and the rocket keeps
// whatever tilt it has when input is released (no auto-centre). The payout multiplier
// reads only the scalar velocity, so steering never affects it.
export const STEER_ROT_SPEED_GROUND = math.rad(4); // roll rate at the pad (rad/s) — extremely weak
export const STEER_ROT_SPEED_SPACE = math.rad(30); // roll rate in space (rad/s) — responsive
export const STEER_SPACE_HEIGHT = 50; // studs above the pad where roll authority reaches full

// Seconds the camera lingers on the exploding rocket (loss) before swinging back
// to the player. Shared so the server reset and the client camera restore agree.
export const EXPLOSION_VIEW_DELAY = 1.5;
