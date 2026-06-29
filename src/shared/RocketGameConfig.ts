// ── Rocket gameplay tuning ──────────────────────────────────────────────────────
// Shared so server (game logic) and client (effects) agree on timing.

// Seconds over which the explosion risk ramps to its max and the progress bar
// fills. Defines the full length of the risk curve.
export const RISK_RAMP_DURATION = 17;

// Seconds between each multiplier tick.
export const MULTIPLIER_TICK_RATE = 1;

// Value the in-game multiplier starts at (1 = base payout before any growth).
export const STARTING_MULTIPLIER = 1;

// Accelerating growth: each tick the multiplier grows by `increment`, and the
// increment itself grows by MULTIPLIER_INCREMENT_GROWTH every tick. So the number
// barely moves at first then climbs faster and faster. The player's Multiplier
// level is intentionally NOT used yet (it will scale these later).
export const MULTIPLIER_START_INCREMENT = 0.05;
export const MULTIPLIER_INCREMENT_GROWTH = 0.05;

// ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
// The rocket rises while the button is held: velocity starts at 0, ramps by
// ROCKET_ACCEL (studs/s²) up to ROCKET_MAX_SPEED (studs/s), then stays constant —
// a slow, accelerating, real-rocket feel. Both will later be scaled by the player's
// multiplier level via the launch() speedFactor (neutral = 1 for now).
export const ROCKET_ACCEL = 6;
export const ROCKET_MAX_SPEED = 60;

// Seconds the camera lingers on the exploding rocket (loss) before swinging back
// to the player. Shared so the server reset and the client camera restore agree.
export const EXPLOSION_VIEW_DELAY = 1.5;
