-- Compiled with roblox-ts v3.0.0
-- ── Cheat Configuration ───────────────────────────────────────────────────────
-- Mettre à true pour activer les cheats en développement.
-- Penser à tout remettre à false avant de publier.
-- Les cheats purement client (touches de test, etc.) vivent dans
-- client/ClientCheatConfig — un module client ne peut pas importer ce fichier.
local invincible = false
-- Annonce en console (serveur), au décollage, l'issue DÉJÀ tirée du vol : dans combien
-- de secondes la fusée explosera, le multiplicateur que le vol aura atteint à cet
-- instant, le gain correspondant, et à partir de quand le claim compte comme Perfect
-- Claim. Sert à tester le timing sans jouer à l'aveugle. MUST be false before publishing.
local logExplosionForecast = true
-- Wipe the player's persisted data (Money + progression values) on join — they
-- load in with the default profile every time, and the next regular save
-- overwrites the DataStore with the new state. Useful for re-testing the
-- onboarding flow.
local resetData = true
-- ── Critical Claim ────────────────────────────────────────────────────────────
-- Passe la chance de Critical Claim de CRITICAL_CLAIM_CHANCE (5 %) à
-- boostedCriticalClaimChance : le flash doré + la pluie d'icônes tombent presque une
-- fois sur deux, donc plus besoin d'enchaîner vingt claims pour les voir.
-- MUST be false before publishing.
local boostCriticalClaim = true
local boostedCriticalClaimChance = 0.5
-- ── Game-pass testing ─────────────────────────────────────────────────────────
-- When true, BoostService seeds EVERY player as if they own NO game pass at all —
-- real Roblox ownership is ignored on join, so you start exactly like a brand-new
-- player even on an account that owns every pass. A purchase made in Studio (and
-- BoostService.devOwn) still adds to the set for the rest of the session.
-- Takes priority over `simulateGamePasses`. MUST be false before publishing.
local ignoreGamePasses = true
-- When true, BoostService IGNORES real Roblox game-pass ownership and treats only
-- the ids in `simulatedOwnedPassIds` as owned (empty = own nothing). Lets you test
-- the buy flow from a not-owned state even on an account that owns every pass.
-- A purchase made in Studio (and BoostService.devOwn) still adds to the set.
-- MUST be false before publishing.
local simulateGamePasses = false
local simulatedOwnedPassIds = {}
-- ── Tutorial ──────────────────────────────────────────────────────────────────
-- Force le tutorial à la connexion en IGNORANT la sauvegarde tuto (le joueur le
-- refait même s'il l'a déjà terminé). À utiliser avec `resetData` pour re-tester
-- l'onboarding complet. MUST be false before publishing.
local forceTutorial = true
return {
	invincible = invincible,
	logExplosionForecast = logExplosionForecast,
	resetData = resetData,
	boostCriticalClaim = boostCriticalClaim,
	boostedCriticalClaimChance = boostedCriticalClaimChance,
	ignoreGamePasses = ignoreGamePasses,
	simulateGamePasses = simulateGamePasses,
	simulatedOwnedPassIds = simulatedOwnedPassIds,
	forceTutorial = forceTutorial,
}
