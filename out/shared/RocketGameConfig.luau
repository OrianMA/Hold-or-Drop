-- Compiled with roblox-ts v3.0.0
-- ── Rocket gameplay tuning ──────────────────────────────────────────────────────
-- Shared so server (game logic) and client (effects) agree on timing.
-- Seconds over which the explosion risk ramps to its max and the progress bar
-- fills. Defines the full length of the risk curve.
local RISK_RAMP_DURATION = 17
-- Seconds between each multiplier tick.
local MULTIPLIER_TICK_RATE = 1
-- Value the in-game multiplier starts at (1 = base payout before any growth).
local STARTING_MULTIPLIER = 1
-- Accelerating growth: each tick the multiplier grows by `increment`, and the
-- increment itself grows by MULTIPLIER_INCREMENT_GROWTH every tick. So the number
-- barely moves at first then climbs faster and faster. The player's Multiplier
-- level is intentionally NOT used yet (it will scale these later).
local MULTIPLIER_START_INCREMENT = 0.05
local MULTIPLIER_INCREMENT_GROWTH = 0.05
-- ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
-- The rocket rises while the button is held: velocity starts at 0, ramps by
-- ROCKET_ACCEL (studs/s²) up to ROCKET_MAX_SPEED (studs/s), then stays constant —
-- a slow, accelerating, real-rocket feel. Both will later be scaled by the player's
-- multiplier level via the launch() speedFactor (neutral = 1 for now).
local ROCKET_ACCEL = 6
local ROCKET_MAX_SPEED = 60
-- Seconds the camera lingers on the exploding rocket (loss) before swinging back
-- to the player. Shared so the server reset and the client camera restore agree.
local EXPLOSION_VIEW_DELAY = 1.5
return {
	RISK_RAMP_DURATION = RISK_RAMP_DURATION,
	MULTIPLIER_TICK_RATE = MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER = STARTING_MULTIPLIER,
	MULTIPLIER_START_INCREMENT = MULTIPLIER_START_INCREMENT,
	MULTIPLIER_INCREMENT_GROWTH = MULTIPLIER_INCREMENT_GROWTH,
	ROCKET_ACCEL = ROCKET_ACCEL,
	ROCKET_MAX_SPEED = ROCKET_MAX_SPEED,
	EXPLOSION_VIEW_DELAY = EXPLOSION_VIEW_DELAY,
}
