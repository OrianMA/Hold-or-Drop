-- Compiled with roblox-ts v3.0.0
-- ── Shop balancing ────────────────────────────────────────────────────────────
-- THE place to retune the shop economy. Only numbers live here — the formulas
-- and wiring are in shared/ShopConfig.ts. Because progression stores LEVELS (not
-- values), editing anything below instantly rebalances every player with no save
-- migration.
--
-- Deux formes de courbe de valeur (définies dans ShopConfig, alimentées ici) :
--   • valeur exponentielle : baseValue * valueGrowth ^ level   (BaseCash)
--   • valeur linéaire      : baseValue + level                 (RocketSpeed / Resistance)
--   • prix (chaque stat)   : startPrice * priceGrowth ^ level  (priceGrowth PAR STAT)
-- Chaque stat a sa propre croissance de prix (`priceGrowth`). C'est nécessaire parce
-- que les trois stats se MULTIPLIENT entre elles (revenu = BaseCash × mult(vitesse,
-- temps de vol), et la Resistance rallonge le temps de vol) : avec une croissance
-- unique l'économie s'emballe. Mur raide sur les stats d'argent, mur doux sur la
-- Resistance pour qu'elle offre beaucoup de petits paliers.
-- BaseCash — le gain de base du bouton. Sans plafond.
--   value = baseValue * valueGrowth ^ level   (L0=100, L10≈619, L20≈3.8K)
--   price = startPrice * priceGrowth ^ level  (L0→1 = 50)
--   Invariant : valueGrowth < priceGrowth (1.20 < 1.8) → le prix dépasse la valeur.
local BASE_CASH = {
	baseValue = 100,
	valueGrowth = 1.2,
	startPrice = 50,
	priceGrowth = 1.8,
}
-- Rocket Speed — pilote À LA FOIS la vitesse d'ascension et la vitesse de montée du
-- multiplicateur (le multiplicateur suit la vitesse instantanée de la fusée). Entier,
-- +1 par niveau, sans plafond.
--   value = baseValue + level   (L0=1 → mult ×2.6 à 10 s ; L1=2 → ×4.3 : le premier
--                                achat double littéralement le gain)
--   accel/vitesse max réels = value × les constantes de RocketGameConfig.
--   price = startPrice * priceGrowth ^ level  (L0→1 = 75)
local ROCKET_SPEED = {
	baseValue = 1,
	startPrice = 75,
	priceGrowth = 1.7,
}
-- Resistance — 0..100. Achetée +1 par niveau. Le nombre n'est PAS un pourcentage : il
-- alimente la courbe de shared/ResistanceCurve.ts, qui le convertit en SECONDES DE VOL
-- GARANTIES (c'est ce qu'affiche le shop). La courbe est front-loaded : L1 achète déjà
-- 1.0 s garantie et +1.5 s de survie médiane, L30 n'achète plus rien.
--   value = level (0..100)
--   price = startPrice * priceGrowth ^ level   (L0→1 = 150)
--   Croissance douce (1.35) et prix de départ bas : la Resistance est remise à zéro à
--   chaque rebirth, donc les niveaux qui comptent doivent être atteignables en 2-3 runs.
local RESISTANCE = {
	maxLevel = 100,
	startPrice = 150,
	priceGrowth = 1.35,
}
-- ── Rebirth ──────────────────────────────────────────────────────────────────
-- Reset everything (cash + the 3 stat levels) for a permanent money multiplier.
--   cost(R) = floor(baseCost * costGrowth ^ R)   (R = rebirths already done)
--   mult(R) = multTable[R] for R inside the table, then linear queue of multTail.
-- multTable index 0 = no rebirth (×1). R1→×2, R2→×3, R3→×3.5, … R7→×5.
local REBIRTH = {
	baseCost = 2500,
	costGrowth = 2.4,
	multTable = { 1, 2, 3, 3.5, 4, 4.5, 4.75, 5 },
	multTail = 0.25,
}
-- ── Money multipliers (3 independent additive factors) ────────────────────────
-- Folded into BaseCash via shared/ShopConfig.moneyMult (additive bonus model:
-- each "×N" adds +(N-1)). Game-pass IDs are 0 until authored on the Roblox
-- dashboard — an id of 0 is INERT (treated as not owned, no web call).
-- Community ×2 — membership of the experience's Roblox group, claimed via the
-- CommunityJoinPart ProximityPrompt in each room.
local COMMUNITY = {
	groupId = 963505568,
	mult = 2,
}
-- Money game-pass ladder — the HIGHEST owned tier wins (not stacked). Each value
-- is the TOTAL multiplier of that tier (×2 … ×1024).
local MONEY_TIERS = { {
	mult = 2,
	gamePassId = 1891624935,
}, {
	mult = 4,
	gamePassId = 1893448867,
}, {
	mult = 8,
	gamePassId = 1889872933,
}, {
	mult = 16,
	gamePassId = 1893904460,
}, {
	mult = 32,
	gamePassId = 1889866920,
}, {
	mult = 64,
	gamePassId = 1891528981,
}, {
	mult = 128,
	gamePassId = 1890406985,
}, {
	mult = 256,
	gamePassId = 1890424956,
}, {
	mult = 512,
	gamePassId = 1893634520,
}, {
	mult = 1024,
	gamePassId = 1890592911,
} }
-- Resistance game pass — flat bonus resistance LEVELS added on top of the shop
-- Resistance (id 0 = inert until authored on the dashboard). Capped at maxLevel.
local RESISTANCE_PASS = {
	addLevels = 20,
	gamePassId = 0,
}
return {
	BASE_CASH = BASE_CASH,
	ROCKET_SPEED = ROCKET_SPEED,
	RESISTANCE = RESISTANCE,
	REBIRTH = REBIRTH,
	COMMUNITY = COMMUNITY,
	MONEY_TIERS = MONEY_TIERS,
	RESISTANCE_PASS = RESISTANCE_PASS,
}
