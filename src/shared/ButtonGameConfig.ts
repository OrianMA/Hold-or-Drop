// ── Button gameplay tuning ──────────────────────────────────────────────────────
// Shared so server (game logic) and client (effects) agree on timing.

// Seconds over which the explosion risk ramps to its max and the progress bar
// fills. Defines the full length of the risk curve.
export const RISK_RAMP_DURATION = 17;

// Seconds between each multiplier tick. Each tick adds the player's Multiplier
// (PlayerProgressionService) to the running total.
export const MULTIPLIER_TICK_RATE = 1;

// Value the in-game multiplier starts at (1 = base payout before any growth).
// Each tick then adds the player's Multiplier on top of this.
export const STARTING_MULTIPLIER = 1;
