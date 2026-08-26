-- Compiled with roblox-ts v3.0.0
-- ── Resistance → risk model ──────────────────────────────────────────────────────
-- Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
-- s'accordent sur ce que vaut un niveau de Resistance.
--
-- Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
-- d'explosion de deux façons indépendantes :
--   • safeWindow — secondes de début de vol où le risque est forcé à 0. C'est la valeur
--     montrée au joueur dans le shop ("X s garanties"), donc le levier PRINCIPAL.
--     Somme de deux termes, et c'est tout l'équilibrage de la stat :
--       – un BURST front-loaded : 5 s achetées sur les ~20 premiers niveaux, à raison
--         d'environ +0.5 s par niveau au tout début (L1 = +0.5 s, L5 = +0.4 s), puis
--         un fondu progressif. Pas de marche brutale — la montée se sent niveau après
--         niveau au lieu de tout donner sur L1-L3.
--       – un terme LINÉAIRE : +0.09 s garanti par niveau, du niveau 1 au niveau 100,
--         sans jamais saturer. C'est ce qui empêche le milieu et la fin de courbe de
--         ne "plus rien valoir" — chaque achat bouge le nombre affiché dans le shop.
--   • riskScale  — étire la durée de vol APRÈS la fenêtre : la médiane est multipliée
--     par riskScale^(-1/3) (il faut diviser le risque par 8 pour doubler la durée).
--     Levier SECONDAIRE et BACK-loaded (exposant > 1) : quasi nul avant L20, il prend
--     le relais en fin de courbe là où le burst est épuisé depuis longtemps.
-- À resistance 0 les deux termes sont neutres → loi de vol de base (moyenne 7 s).
--
-- Repères (s garanties / vol moyen / multiplicateur garanti à Rocket Speed 1) :
--   L1  → 0.5 s /  7.5 s / ×1.00    L20  →  6.1 s / 13.3 s / ×1.34
--   L2  → 1.0 s /  8.0 s / ×1.01    L50  →  9.5 s / 17.0 s / ×1.80
--   L5  → 2.3 s /  9.3 s / ×1.05    L100 → 14.0 s / 22.5 s / ×2.67
--   L10 → 4.0 s / 11.0 s / ×1.14
-- Le gain marginal par niveau ne tombe jamais sous ~0.09 s (contre 0.00 s après L30
-- dans l'ancien réglage).
local RESISTANCE_MAX_LEVEL = 100
local RESISTANCE_MAX_REDUCTION = 0.45
local RESISTANCE_REDUCTION_CURVE = 1.2
local RESISTANCE_SAFE_WINDOW_BURST = 5
local RESISTANCE_SAFE_WINDOW_CURVE = 9
local RESISTANCE_SAFE_WINDOW_LINEAR = 9
local RESISTANCE_MAX_SAFE_WINDOW = RESISTANCE_SAFE_WINDOW_BURST + RESISTANCE_SAFE_WINDOW_LINEAR
-- ── Loi de durée de vol ─────────────────────────────────────────────────────────
-- La durée d'un vol est tirée d'un coup au décollage dans une cloche de Gauss sur une
-- échelle MULTIPLICATIVE du temps (voir `rollExplosionTime`, ButtonInGameModule) :
--   vol = safeWindow + médiane × riskScale^(-1/3) × e^(σ·Z),  Z ~ N(0,1)
--
-- Ces constantes vivaient côté serveur. Elles sont ici parce que le CLIENT en a besoin
-- pour calibrer l'escalade de paiement (client/ui/PayoutTiers, §6.4) sur la durée de vol
-- RÉELLE du joueur — donc en tenant compte de sa Resistance, pas seulement de sa Rocket
-- Speed. Une seule source de vérité : le serveur les importe d'ici.
local FLIGHT_TIME_MEAN = 7
local FLIGHT_TIME_SIGMA = 0.35
-- Médiane telle que la MOYENNE vaille FLIGHT_TIME_MEAN — sur une échelle multiplicative,
-- moyenne = médiane × e^(σ²/2). Régler σ ne déplace donc pas la moyenne.
local FLIGHT_TIME_MEDIAN = FLIGHT_TIME_MEAN * math.exp(-(FLIGHT_TIME_SIGMA * FLIGHT_TIME_SIGMA) / 2)
-- Durée de vol au quantile `z` de la loi normale centrée réduite (z = 0 → médiane,
-- z = 1.28 → 90ᵉ centile…). C'est la fonction inverse du tirage : elle répond à
-- "quelle durée de vol un joueur de cette Resistance bat-il X % du temps ?".
local resistanceRiskParams
local function flightTimeAtZ(resistance, z)
	local params = resistanceRiskParams(resistance)
	return params.safeWindow + FLIGHT_TIME_MEDIAN * params.riskScale ^ (-1 / 3) * math.exp(FLIGHT_TIME_SIGMA * z)
end
-- Durée de vol MOYENNE pour cette Resistance. Forme fermée : E[e^(σZ)] = e^(σ²/2)
-- annule exactement le e^(-σ²/2) de la médiane, donc σ disparaît et il reste
-- `safeWindow + MEAN × riskScale^(-1/3)`. Reproduit les repères du tableau ci-dessus
-- (L20 → 13.3 s, L50 → 17.0 s, L100 → 22.5 s).
local function expectedFlightTime(resistance)
	local params = resistanceRiskParams(resistance)
	return params.safeWindow + FLIGHT_TIME_MEAN * params.riskScale ^ (-1 / 3)
end
function resistanceRiskParams(resistance)
	local n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1)
	local reduction = RESISTANCE_MAX_REDUCTION * n ^ RESISTANCE_REDUCTION_CURVE
	local safeWindow = RESISTANCE_SAFE_WINDOW_BURST * (1 - (1 - n) ^ RESISTANCE_SAFE_WINDOW_CURVE) + RESISTANCE_SAFE_WINDOW_LINEAR * n
	return {
		riskScale = 1 - reduction,
		safeWindow = safeWindow,
	}
end
return {
	flightTimeAtZ = flightTimeAtZ,
	expectedFlightTime = expectedFlightTime,
	resistanceRiskParams = resistanceRiskParams,
	RESISTANCE_MAX_LEVEL = RESISTANCE_MAX_LEVEL,
	RESISTANCE_MAX_REDUCTION = RESISTANCE_MAX_REDUCTION,
	RESISTANCE_REDUCTION_CURVE = RESISTANCE_REDUCTION_CURVE,
	RESISTANCE_SAFE_WINDOW_BURST = RESISTANCE_SAFE_WINDOW_BURST,
	RESISTANCE_SAFE_WINDOW_CURVE = RESISTANCE_SAFE_WINDOW_CURVE,
	RESISTANCE_SAFE_WINDOW_LINEAR = RESISTANCE_SAFE_WINDOW_LINEAR,
	RESISTANCE_MAX_SAFE_WINDOW = RESISTANCE_MAX_SAFE_WINDOW,
	FLIGHT_TIME_MEAN = FLIGHT_TIME_MEAN,
	FLIGHT_TIME_SIGMA = FLIGHT_TIME_SIGMA,
	FLIGHT_TIME_MEDIAN = FLIGHT_TIME_MEDIAN,
}
