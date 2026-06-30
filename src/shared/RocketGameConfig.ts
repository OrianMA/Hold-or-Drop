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

// Seconds the camera lingers on the exploding rocket (loss) before swinging back
// to the player. Shared so the server reset and the client camera restore agree.
export const EXPLOSION_VIEW_DELAY = 1.5;
