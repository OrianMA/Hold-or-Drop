// ── Resistance → risk model ──────────────────────────────────────────────────────
// Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
// s'accordent sur ce que vaut un niveau de Resistance.
//
// Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
// d'explosion de deux façons indépendantes :
//   • safeWindow — secondes de début de vol où le risque est forcé à 0. FRONT-loaded :
//     les premiers niveaux achètent l'essentiel de la fenêtre, les derniers presque
//     rien. C'est la valeur montrée au joueur dans le shop ("X s garanties").
//   • riskScale  — étire la durée de vol APRÈS la fenêtre : la médiane est multipliée
//     par riskScale^(-1/3) (il faut diviser le risque par 8 pour doubler la durée).
//     Levier SECONDAIRE, illisible seul — d'où le basculement de poids vers safeWindow.
// À resistance 0 les deux termes sont neutres → loi de vol de base (moyenne 4 s).
//
// Repères : L1 → 0.5 s garanties / durée moyenne 4.7 s (contre 4.0 s à L0).
//           L5 → 2.0 s / 6.7 s.  L10 → 3.1 s / 8.3 s.  L30 → 4.0 s / 10.3 s (saturé).

export const RESISTANCE_MAX_LEVEL = 100;
export const RESISTANCE_MAX_REDUCTION = 0.75; // risque plancher ×0.25 au niveau 100
export const RESISTANCE_REDUCTION_CURVE = 13; // ↑ = plus front-loaded
export const RESISTANCE_MAX_SAFE_WINDOW = 4; // secondes garanties au niveau 100
export const RESISTANCE_SAFE_WINDOW_CURVE = 14; // ↑ = plus front-loaded

export interface RiskParams {
	readonly riskScale: number;
	readonly safeWindow: number;
}

export function resistanceRiskParams(resistance: number): RiskParams {
	const n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1);
	const reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ** RESISTANCE_REDUCTION_CURVE);
	const safeWindow = RESISTANCE_MAX_SAFE_WINDOW * (1 - (1 - n) ** RESISTANCE_SAFE_WINDOW_CURVE);
	return { riskScale: 1 - reduction, safeWindow };
}
