// ── Stage timing — shared between server (game logic) and client (progress-bar markers) ─────────
// Only duration & tickInterval live here.
// multiplicatorAdded is defined per-button via Roblox attributes (Level1..Level5).

export interface StageTimingConfig {
	duration: number; // seconds this stage lasts before the next one starts
	tickInterval: number; // seconds between each multiplier tick in this stage
}

export const STAGE_TIMING_CONFIGS: StageTimingConfig[] = [
	{ duration: 5, tickInterval: 1.0 }, // lent
	{ duration: 4, tickInterval: 0.75 },
	{ duration: 4, tickInterval: 0.6 },
	{ duration: 4, tickInterval: 0.5 },
	{ duration: 0, tickInterval: 0.4 }, // rapide — last stage, runs forever
];

// Total duration — defines the full length of the risk curve and the progress bar
export const TOTAL_STAGE_DURATION = (() => {
	let total = 0;
	for (const s of STAGE_TIMING_CONFIGS) total += s.duration;
	return total;
})();
