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
local function resistanceRiskParams(resistance)
	local n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1)
	local reduction = RESISTANCE_MAX_REDUCTION * n ^ RESISTANCE_REDUCTION_CURVE
	local safeWindow = RESISTANCE_SAFE_WINDOW_BURST * (1 - (1 - n) ^ RESISTANCE_SAFE_WINDOW_CURVE) + RESISTANCE_SAFE_WINDOW_LINEAR * n
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
	RESISTANCE_SAFE_WINDOW_BURST = RESISTANCE_SAFE_WINDOW_BURST,
	RESISTANCE_SAFE_WINDOW_CURVE = RESISTANCE_SAFE_WINDOW_CURVE,
	RESISTANCE_SAFE_WINDOW_LINEAR = RESISTANCE_SAFE_WINDOW_LINEAR,
	RESISTANCE_MAX_SAFE_WINDOW = RESISTANCE_MAX_SAFE_WINDOW,
}
