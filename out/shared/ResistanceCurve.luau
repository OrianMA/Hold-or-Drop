-- Compiled with roblox-ts v3.0.0
-- ── Resistance → risk model ──────────────────────────────────────────────────────
-- Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
-- s'accordent sur ce que vaut un niveau de Resistance.
--
-- Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
-- d'explosion de deux façons indépendantes :
--   • safeWindow — secondes de début de vol où le risque est forcé à 0. C'est la
--     valeur montrée au joueur ("X s garanties").
--   • riskScale  — met à l'échelle toute la courbe de risque APRÈS la fenêtre. Levier
--     secondaire : la survie médiane ne croît qu'en riskScale^(-1/3), donc il ne peut
--     pas être rendu lisible seul.
-- À resistance 0 les deux termes sont neutres → courbe identique à celle d'origine.
local RESISTANCE_MAX_LEVEL = 100
local RESISTANCE_MAX_REDUCTION = 0.99
local RESISTANCE_REDUCTION_CURVE = 12
local RESISTANCE_MAX_SAFE_WINDOW = 15
local RESISTANCE_SAFE_WINDOW_CURVE = 2.5
local function resistanceRiskParams(resistance)
	local n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1)
	local reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ^ RESISTANCE_REDUCTION_CURVE)
	local safeWindow = n ^ RESISTANCE_SAFE_WINDOW_CURVE * RESISTANCE_MAX_SAFE_WINDOW
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
