// ── Cheat Configuration ───────────────────────────────────────────────────────
// Mettre à true pour activer les cheats en développement.
// Penser à tout remettre à false avant de publier.

export const invincible = false; // le bouton n'explosera jamais

// Wipe the player's persisted data (Money + UnlockedButtons) on join — they
// load in with the default profile every time, and the next regular save
// overwrites the DataStore with the new state. Useful for re-testing the
// onboarding flow.
export const resetData = true;
