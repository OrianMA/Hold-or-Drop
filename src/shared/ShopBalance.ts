// ── Shop balancing ────────────────────────────────────────────────────────────
// THE place to retune the shop economy. Only numbers live here — the formulas
// and wiring are in shared/ShopConfig.ts. Because progression stores LEVELS (not
// values), editing anything below instantly rebalances every player with no save
// migration.
//
// Deux formes de courbe de valeur (définies dans ShopConfig, alimentées ici) :
//   • valeur exponentielle : baseValue * valueGrowth ^ level   (BaseCash)
//   • valeur linéaire      : baseValue + level                 (RocketSpeed / Resistance)
//   • prix (chaque stat)   : startPrice * priceGrowth ^ level  (priceGrowth PAR STAT)

// Chaque stat a sa propre croissance de prix (`priceGrowth`). C'est nécessaire parce
// que les trois stats se MULTIPLIENT entre elles (revenu = BaseCash × mult(vitesse,
// temps de vol), et la Resistance rallonge le temps de vol) : avec une croissance
// unique l'économie s'emballe. Mur raide sur les stats d'argent, mur doux sur la
// Resistance pour qu'elle offre beaucoup de petits paliers.

// BaseCash — le gain de base du bouton. Sans plafond.
//   value = baseValue * valueGrowth ^ level   (L0=100, L10≈619, L20≈3.8K)
//   price = startPrice * priceGrowth ^ level  (L0→1 = 50)
//   Invariant : valueGrowth < priceGrowth (1.20 < 1.8) → le prix dépasse la valeur.
export const BASE_CASH = {
	baseValue: 100,
	valueGrowth: 1.2,
	startPrice: 50,
	priceGrowth: 1.8,
};

// Rocket Speed — pilote À LA FOIS la vitesse d'ascension et la vitesse de montée du
// multiplicateur (le multiplicateur suit la vitesse instantanée de la fusée). Entier,
// +1 par niveau, sans plafond.
//   value = baseValue + level   (L0=1 → mult ×2.6 à 10 s ; L1=2 → ×4.3 : le premier
//                                achat double littéralement le gain)
//   accel/vitesse max réels = value × les constantes de RocketGameConfig.
//   price = startPrice * priceGrowth ^ level  (L0→1 = 75)
export const ROCKET_SPEED = {
	baseValue: 1,
	startPrice: 75,
	priceGrowth: 1.7,
};

// Resistance — 0..100. Achetée +1 par niveau. Le nombre n'est PAS un pourcentage : il
// alimente la courbe de shared/ResistanceCurve.ts, qui le convertit en SECONDES DE VOL
// GARANTIES (c'est ce qu'affiche le shop). La courbe est front-loaded : L1 achète déjà
// 1.0 s garantie et +1.5 s de survie médiane, L30 n'achète plus rien.
//   value = level (0..100)
//   price = startPrice * priceGrowth ^ level   (L0→1 = 150)
//   Croissance douce (1.35) et prix de départ bas : la Resistance est remise à zéro à
//   chaque rebirth, donc les niveaux qui comptent doivent être atteignables en 2-3 runs.
export const RESISTANCE = {
	maxLevel: 100,
	startPrice: 150,
	priceGrowth: 1.35,
};

// ── Rebirth ──────────────────────────────────────────────────────────────────
// Remet à zéro l'argent + les 3 niveaux de stat contre un multiplicateur d'argent
// permanent.
//   cost(R) = floor(baseCost * costGrowth ^ R)   (R = rebirths déjà faits)
//   mult(R) = multGrowth ^ R                     (R0 → ×1, R1 → ×8, R2 → ×64…)
//
// multGrowth = 8 est calibré pour que le joueur RETROUVE son revenu de pointe en ~3
// runs après un rebirth (il repart avec BaseCash/RocketSpeed/Resistance à zéro, donc
// un ratio faible le condamnerait à passer la moitié du cycle à racheter l'existant).
// costGrowth = 38 dépasse volontairement la croissance du revenu de pointe : les
// cycles s'allongent progressivement (R1 ~5 min, R4 ~8 min, R7 ~16 min) au lieu de
// rester plats. baseCost 20000 fixe le PREMIER rebirth à ~9.5 min et n'est pas touché
// par ce réglage. Voir
// docs/superpowers/specs/2026-07-22-progression-rebalance-design.md §4.
export const REBIRTH = {
	baseCost: 20000,
	costGrowth: 38,
	multGrowth: 8,
};

// ── Money multipliers (rebirth multiplicative, boosts additive) ───────────────
// Folded into BaseCash via shared/ShopConfig.moneyMult:
//   moneyMult = multRebirth * (1 + communityBonus + tierBonus)
// MultRebirth MULTIPLIES the whole factor; community and the money-tier pass only
// ADD their "+(N-1)" bonus inside the boost factor, so a ×2 pass stays worth ×2 at
// any rebirth level instead of being swamped by a large MultRebirth. Game-pass IDs
// are 0 until authored on the Roblox dashboard — an id of 0 is INERT (treated as
// not owned, no web call).

// Community ×2 — membership of the experience's Roblox group, claimed via the
// CommunityJoinPart ProximityPrompt in each room.
export const COMMUNITY = { groupId: 963505568, mult: 2 };

// Money game-pass ladder — the HIGHEST owned tier wins (not stacked). Each value
// is the TOTAL multiplier of that tier (×2 … ×1024).
export const MONEY_TIERS: ReadonlyArray<{ mult: number; gamePassId: number }> = [
	{ mult: 2, gamePassId: 1891624935 },
	{ mult: 4, gamePassId: 1893448867 },
	{ mult: 8, gamePassId: 1889872933 },
	{ mult: 16, gamePassId: 1893904460 },
	{ mult: 32, gamePassId: 1889866920 },
	{ mult: 64, gamePassId: 1891528981 },
	{ mult: 128, gamePassId: 1890406985 },
	{ mult: 256, gamePassId: 1890424956 },
	{ mult: 512, gamePassId: 1893634520 },
	{ mult: 1024, gamePassId: 1890592911 },
];

// Resistance game pass — flat bonus resistance LEVELS added on top of the shop
// Resistance (id 0 = inert until authored on the dashboard). Capped at maxLevel.
export const RESISTANCE_PASS = { addLevels: 20, gamePassId: 0 };
