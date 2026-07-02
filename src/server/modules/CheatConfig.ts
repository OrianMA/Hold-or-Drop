// ── Cheat Configuration ───────────────────────────────────────────────────────
// Mettre à true pour activer les cheats en développement.
// Penser à tout remettre à false avant de publier.

export const invincible = false; // le bouton n'explosera jamais

// Wipe the player's persisted data (Money + progression values) on join — they
// load in with the default profile every time, and the next regular save
// overwrites the DataStore with the new state. Useful for re-testing the
// onboarding flow.
export const resetData = false;

// ── Game-pass testing ─────────────────────────────────────────────────────────
// When true, BoostService seeds EVERY player as if they own NO game pass at all —
// real Roblox ownership is ignored on join, so you start exactly like a brand-new
// player even on an account that owns every pass. A purchase made in Studio (and
// BoostService.devOwn) still adds to the set for the rest of the session.
// Takes priority over `simulateGamePasses`. MUST be false before publishing.
export const ignoreGamePasses = false;

// When true, BoostService IGNORES real Roblox game-pass ownership and treats only
// the ids in `simulatedOwnedPassIds` as owned (empty = own nothing). Lets you test
// the buy flow from a not-owned state even on an account that owns every pass.
// A purchase made in Studio (and BoostService.devOwn) still adds to the set.
// MUST be false before publishing.
export const simulateGamePasses = false;
export const simulatedOwnedPassIds: number[] = [];
