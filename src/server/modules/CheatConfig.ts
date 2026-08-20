// ── Cheat Configuration ───────────────────────────────────────────────────────
// Mettre à true pour activer les cheats en développement.
// Penser à tout remettre à false avant de publier.
// Les cheats purement client (touches de test, etc.) vivent dans
// client/ClientCheatConfig — un module client ne peut pas importer ce fichier.

export const invincible = false; // le bouton n'explosera jamais

// Annonce en console (serveur), au décollage, l'issue DÉJÀ tirée du vol : dans combien
// de secondes la fusée explosera, le multiplicateur que le vol aura atteint à cet
// instant, le gain correspondant, et à partir de quand le claim compte comme Perfect
// Claim. Sert à tester le timing sans jouer à l'aveugle. MUST be false before publishing.
export const logExplosionForecast = true;

// Wipe the player's persisted data (Money + progression values) on join — they
// load in with the default profile every time, and the next regular save
// overwrites the DataStore with the new state. Useful for re-testing the
// onboarding flow.
export const resetData = true;

// ── Critical Claim ────────────────────────────────────────────────────────────
// Passe la chance de Critical Claim de CRITICAL_CLAIM_CHANCE (5 %) à
// boostedCriticalClaimChance : le flash doré + la pluie d'icônes tombent presque une
// fois sur deux, donc plus besoin d'enchaîner vingt claims pour les voir.
// MUST be false before publishing.
export const boostCriticalClaim = false;
export const boostedCriticalClaimChance = 0.5;

// ── Game-pass testing ─────────────────────────────────────────────────────────
// When true, BoostService seeds EVERY player as if they own NO game pass at all —
// real Roblox ownership is ignored on join, so you start exactly like a brand-new
// player even on an account that owns every pass. A purchase made in Studio (and
// BoostService.devOwn) still adds to the set for the rest of the session.
// Takes priority over `simulateGamePasses`. MUST be false before publishing.
export const ignoreGamePasses = true;

// When true, BoostService IGNORES real Roblox game-pass ownership and treats only
// the ids in `simulatedOwnedPassIds` as owned (empty = own nothing). Lets you test
// the buy flow from a not-owned state even on an account that owns every pass.
// A purchase made in Studio (and BoostService.devOwn) still adds to the set.
// MUST be false before publishing.
export const simulateGamePasses = false;
export const simulatedOwnedPassIds: number[] = [];

// ── Tutorial ──────────────────────────────────────────────────────────────────
// Force le tutorial à la connexion en IGNORANT la sauvegarde tuto (le joueur le
// refait même s'il l'a déjà terminé). À utiliser avec `resetData` pour re-tester
// l'onboarding complet. MUST be false before publishing.
export const forceTutorial = true;

// ── Mega Rocket ───────────────────────────────────────────────────────────────
// Raccourcit l'intervalle entre deux Mega Rockets (normalement
// MEGA_ROCKET_INTERVAL = 6 min) pour pouvoir tester l'événement en quelques
// secondes. `undefined` = intervalle normal. MUST be undefined before publishing.
export const megaRocketInterval: number | undefined = undefined;

// Touche G (client/MegaRocketCheat) : ramène le compte à rebours de la Mega Rocket
// à `megaRocketCheatDelay` secondes, à la demande. Sans toucher à la cadence
// normale — l'événement suivant repart sur l'intervalle habituel.
// Le serveur n'écoute MegaRocketCheatEvent que si ce flag est vrai.
// MUST be false before publishing.
export const megaRocketCheatKey = true;
export const megaRocketCheatDelay = 3;
