-- Compiled with roblox-ts v3.0.0
-- ── Stage timing — shared between server (game logic) and client (progress-bar markers) ─────────
-- Only duration & tickInterval live here.
-- multiplicatorAdded is defined per-button via Roblox attributes (Level1..Level5).
local STAGE_TIMING_CONFIGS = { {
	duration = 5,
	tickInterval = 1.0,
}, {
	duration = 4,
	tickInterval = 0.75,
}, {
	duration = 4,
	tickInterval = 0.6,
}, {
	duration = 4,
	tickInterval = 0.5,
}, {
	duration = 0,
	tickInterval = 0.4,
} }
-- Total duration — defines the full length of the risk curve and the progress bar
local TOTAL_STAGE_DURATION = (function()
	local total = 0
	for _, s in STAGE_TIMING_CONFIGS do
		total += s.duration
	end
	return total
end)()
return {
	STAGE_TIMING_CONFIGS = STAGE_TIMING_CONFIGS,
	TOTAL_STAGE_DURATION = TOTAL_STAGE_DURATION,
}
