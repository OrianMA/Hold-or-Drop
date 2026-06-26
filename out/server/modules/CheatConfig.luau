-- Compiled with roblox-ts v3.0.0
-- ── Cheat Configuration ───────────────────────────────────────────────────────
-- Mettre à true pour activer les cheats en développement.
-- Penser à tout remettre à false avant de publier.
local invincible = false
-- Wipe the player's persisted data (Money + progression values) on join — they
-- load in with the default profile every time, and the next regular save
-- overwrites the DataStore with the new state. Useful for re-testing the
-- onboarding flow.
local resetData = false
-- ── Game-pass testing ─────────────────────────────────────────────────────────
-- When true, BoostService IGNORES real Roblox game-pass ownership and treats only
-- the ids in `simulatedOwnedPassIds` as owned (empty = own nothing). Lets you test
-- the buy flow from a not-owned state even on an account that owns every pass.
-- A purchase made in Studio (and BoostService.devOwn) still adds to the set.
-- MUST be false before publishing.
local simulateGamePasses = false
local simulatedOwnedPassIds = {}
return {
	invincible = invincible,
	resetData = resetData,
	simulateGamePasses = simulateGamePasses,
	simulatedOwnedPassIds = simulatedOwnedPassIds,
}
