-- Compiled with roblox-ts v3.0.0
-- ── Button gameplay tuning ──────────────────────────────────────────────────────
-- Shared so server (game logic) and client (effects) agree on timing.
-- Seconds over which the explosion risk ramps to its max and the progress bar
-- fills. Defines the full length of the risk curve.
local RISK_RAMP_DURATION = 17
-- Seconds between each multiplier tick. Each tick adds the player's Multiplier
-- (PlayerProgressionService) to the running total.
local MULTIPLIER_TICK_RATE = 1
-- Value the in-game multiplier starts at (1 = base payout before any growth).
-- Each tick then adds the player's Multiplier on top of this.
local STARTING_MULTIPLIER = 1
return {
	RISK_RAMP_DURATION = RISK_RAMP_DURATION,
	MULTIPLIER_TICK_RATE = MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER = STARTING_MULTIPLIER,
}
