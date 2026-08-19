-- Compiled with roblox-ts v3.0.0
-- ── Resistance → risk model ──────────────────────────────────────────────────────
-- Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
-- s'accordent sur ce que vaut un niveau de Resistance.
--
-- Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
-- d'explosion de deux façons indépendantes :
--   • safeWindow — secondes de début de vol où le risque est forcé à 0. TRÈS front-loaded :
--     les 3-4 premiers niveaux achètent l'essentiel de la fenêtre, les suivants presque
--     rien. C'est délibéré — les toutes premières améliorations doivent faire sentir un
--     saut net de durée, pas une progression diluée sur 30 niveaux.
--     C'est la valeur montrée au joueur dans le shop ("X s garanties").
--   • riskScale  — étire la durée de vol APRÈS la fenêtre : la médiane est multipliée
--     par riskScale^(-1/3) (il faut diviser le risque par 8 pour doubler la durée).
--     Levier SECONDAIRE, illisible seul — d'où le basculement de poids vers safeWindow.
-- À resistance 0 les deux termes sont neutres → loi de vol de base (moyenne 7 s).
--
-- Repères : L1 → 2.4 s garanties / durée moyenne 9.7 s (contre 7.0 s à L0).
--           L2 → 3.9 s / 11.4 s.  L3 → 4.8 s / 12.5 s.  L5 → 5.6 s / 13.7 s.
--           L10 → 6.0 s / 15.2 s.  L30 → 6.0 s / 17.0 s (saturé, la suite vient de riskScale).
local RESISTANCE_MAX_LEVEL = 100
local RESISTANCE_MAX_REDUCTION = 0.75
local RESISTANCE_REDUCTION_CURVE = 13
local RESISTANCE_MAX_SAFE_WINDOW = 6
local RESISTANCE_SAFE_WINDOW_CURVE = 52
local function resistanceRiskParams(resistance)
	local n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1)
	local reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ^ RESISTANCE_REDUCTION_CURVE)
	local safeWindow = RESISTANCE_MAX_SAFE_WINDOW * (1 - (1 - n) ^ RESISTANCE_SAFE_WINDOW_CURVE)
	return {
		riskScale = 1 - reduction,
		safeWindow = safeWindow,
	}
end
return {
	resistanceRiskParams = resistanceRiskParams,
	RESISTANCE_MAX_LEVEL = RESISTANCE_MAX_LEVEL,
	RESISTANCE_MAX_REDUCTION = RESISTANCE_MAX_REDUCTION,
	RESISTANCE_REDUCTION_CURVE = RESISTANCE_REDUCTION_CURVE,
	RESISTANCE_MAX_SAFE_WINDOW = RESISTANCE_MAX_SAFE_WINDOW,
	RESISTANCE_SAFE_WINDOW_CURVE = RESISTANCE_SAFE_WINDOW_CURVE,
}
