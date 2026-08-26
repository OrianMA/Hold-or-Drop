// ── Paliers de paiement (écran de fin) ─────────────────────────────────────────
//
// Décrit l'ESCALADE de l'animation de paiement : plus le run est gros, plus le son est
// fort et aigu, plus il y a de billets. Consommé par EndGameAnimation (§6.4), qui
// déclenche un palier chaque fois que le compteur franchit son seuil pendant le count-up.
//
// ── Pourquoi des CENTILES et pas des multiplicateurs fixes ────────────────────
// Le multiplicateur atteint dépend de DEUX stats : la Rocket Speed (linéaire —
// `mult = 1 + rocketSpeed × G(durée)`) et la Resistance (qui allonge la durée de vol).
// Une échelle de seuils fixes (×2/×10/×100) serait donc inatteignable en early et
// saturée en late : l'animation redeviendrait identique à chaque run.
//
// Un ratio à la moyenne (`mult / moyenne`) ne suffit pas non plus : la `safeWindow` de
// la Resistance est DÉTERMINISTE, donc elle écrase la variance relative. À Resistance 0
// le meilleur centile vaut ~3.9× la moyenne, à Resistance 100 seulement ~1.5× — un
// palier "≥ 2.5× ta moyenne" deviendrait inatteignable en fin de progression, et
// acheter de la Resistance rendrait les paiements MOINS spectaculaires.
//
// La réponse : chaque palier est un CENTILE de la propre distribution de vol du joueur.
// "Ce run bat 90 % de tes runs" veut dire la même chose à toute Rocket Speed et à toute
// Resistance — l'escalade est donc calibrée en permanence. Et c'est analytique, pas
// simulé : la durée de vol au centile p est `safeWindow + médiane × e^(σ·z_p)`
// (shared/ResistanceCurve.flightTimeAtZ), qu'on repasse dans `multiplierAfter`.
//
// Rien n'affiche jamais le seuil au joueur — les paliers ne pilotent que le son et les
// particules — donc on ne perd aucune lisibilité en abandonnant les nombres ronds.

import { multiplierAfter, STARTING_MULTIPLIER } from "shared/RocketGameConfig";
import { flightTimeAtZ } from "shared/ResistanceCurve";

// Quantiles de la loi normale centrée réduite pour les centiles visés. Le palier i se
// déclenche quand le run bat TIER_PERCENTILES[i] de ses runs.
//   z ≈  -0.385 / 0.253 / 0.772 / 1.282 / 1.751 / 2.326 / 2.748 / 3.291
const TIER_PERCENTILE_Z = [-0.3853, 0.2533, 0.7722, 1.2816, 1.7507, 2.3263, 2.7478, 3.2905];

// Nombre de paliers effectivement joués : les plus hauts franchis. Au-delà de 3
// l'escalade s'étale trop et le count-up (plafonné à ~1.2 s) part en bouillie.
const MAX_PLAYED = 3;

// Le palier 0 n'a pas de centile : il est TOUJOURS franchi (seuil = multiplicateur de
// départ). Tout paiement déclenche donc au moins un son et une pluie légère.
const TIER_COUNT = TIER_PERCENTILE_Z.size() + 1;
const LAST_INDEX = TIER_COUNT - 1;

// À partir de cet index, le palier ajoute le son "gros lot" (centile 90 → top 10 %).
const BIG_REWARD_INDEX = 4;
// À partir de cet index, des lingots d'or tombent avec les billets (centile 78).
const GOLD_RAIN_INDEX = 3;
// Le CLIMAX d'une escalade qui atteint cet index (centile 96 → top 4 %) déclenche le
// DÉLUGE de lingots : la pluie de billets est remplacée par une pluie d'or dense.
const INGOT_DOWNPOUR_INDEX = 5;

// ── Bornes d'intensité ─────────────────────────────────────────────────────────
// Tout est interpolé linéairement de l'index 0 au dernier index, plutôt qu'écrit
// palier par palier : la monotonie est garantie et le tuning tient en deux valeurs.
const PITCH_MIN = 1;
const PITCH_MAX = 1.3;
const VOLUME_MIN = 0.5;
const VOLUME_MAX = 1;
const BURST_MIN = 6; // billets de la gerbe
const BURST_MAX = 36;
// Dépassement du UIScale au déclenchement du palier. C'est le "punch" du montant.
// Il passe par un UIScale et NON par TextSize : Roblox plafonne TextSize à 100, et
// BaseCashText démarre déjà à 85 — un dépassement sur la taille serait donc écrêté,
// pile sur les gros paliers. UIScale n'a pas cette limite.
const PUNCH_MIN = 1.12;
const PUNCH_MAX = 1.4;

const RAIN_MIN = 8; // billets de la pluie
// Le palier max demande RAIN_MAX billets + RAIN_MAX / 2 en lingots, soit ~55 gouttes :
// ça doit tenir sous MAX_LIVE_DROPS (CriticalRain) pour que le plus gros palier
// s'affiche en entier sans avoir à évincer sa propre pluie d'or.
const RAIN_MAX = 40;

// Déluge de lingots du climax. Il REMPLACE la pluie de billets sur ce palier — une
// pluie d'or pure se lit mieux qu'un mélange, et ça tient sous le plafond de gouttes.
const INGOT_DOWNPOUR_MIN = 40;
const INGOT_DOWNPOUR_MAX = 62;

// Rouge clair (couleur historique du count-up) → or plein.
const COLOR_MIN = Color3.fromRGB(255, 64, 64);
const COLOR_MAX = Color3.fromRGB(255, 200, 60);

export interface PayoutTier {
	index: number; // rang absolu — c'est lui qui pilote l'intensité
	threshold: number; // multiplicateur à atteindre pour déclencher ce palier
	pitch: number; // PlaybackSpeed du son cash
	volume: number;
	burstCount: number; // billets de MoneyBurst
	rainCount: number; // billets de CriticalRain
	color: Color3; // couleur prise par BaseCashText
	punch: number; // dépassement du UIScale à l'impact
	goldRain: boolean; // lingots en plus de la pluie de billets
	bigReward: boolean; // joue aussi le son Big reward
	// Déluge de lingots à la place de la pluie de billets. Réservé au DERNIER palier
	// joué d'une grosse escalade, donc au plus une fois par paiement.
	ingotDownpour: number; // 0 = pas de déluge, sinon le nombre de lingots
}

function lerp(from: number, to: number, t: number): number {
	return from + (to - from) * t;
}

// Multiplicateur que ce joueur atteint au centile `z` de ses vols. C'est le seuil du
// palier : il suit automatiquement la Rocket Speed ET la Resistance.
function thresholdAt(index: number, rocketSpeed: number, resistance: number): number {
	if (index === 0) return STARTING_MULTIPLIER; // toujours franchi
	return multiplierAfter(rocketSpeed, flightTimeAtZ(resistance, TIER_PERCENTILE_Z[index - 1]));
}

function tierAt(index: number, rocketSpeed: number, resistance: number, isClimax: boolean): PayoutTier {
	const t = LAST_INDEX > 0 ? index / LAST_INDEX : 0;
	const downpour = isClimax && index >= INGOT_DOWNPOUR_INDEX;
	return {
		index,
		threshold: thresholdAt(index, rocketSpeed, resistance),
		pitch: lerp(PITCH_MIN, PITCH_MAX, t),
		volume: lerp(VOLUME_MIN, VOLUME_MAX, t),
		burstCount: math.floor(lerp(BURST_MIN, BURST_MAX, t) + 0.5),
		rainCount: math.floor(lerp(RAIN_MIN, RAIN_MAX, t) + 0.5),
		color: COLOR_MIN.Lerp(COLOR_MAX, t),
		punch: lerp(PUNCH_MIN, PUNCH_MAX, t),
		// Le déluge remplace la pluie mixte : pas de lingots "en plus" par-dessus.
		goldRain: !downpour && index >= GOLD_RAIN_INDEX,
		bigReward: index >= BIG_REWARD_INDEX,
		ingotDownpour: downpour ? math.floor(lerp(INGOT_DOWNPOUR_MIN, INGOT_DOWNPOUR_MAX, t) + 0.5) : 0,
	};
}

// Rang du plus haut palier franchi (0 au minimum — le palier 0 l'est toujours). Sert à
// doser ce qui dépend de l'ampleur globale sans rejouer l'escalade (nombre de liasses,
// gerbe finale).
export function topTierIndex(multiplier: number, rocketSpeed: number, resistance: number): number {
	let top = 0;
	for (let i = 1; i < TIER_COUNT; i++) {
		if (multiplier >= thresholdAt(i, rocketSpeed, resistance)) top = i;
	}
	return top;
}

// Paliers à JOUER, du plus bas au plus haut : les MAX_PLAYED derniers franchis.
export function tiersCrossed(multiplier: number, rocketSpeed: number, resistance: number): PayoutTier[] {
	const top = topTierIndex(multiplier, rocketSpeed, resistance);
	const first = math.max(0, top - MAX_PLAYED + 1);

	const tiers: PayoutTier[] = [];
	for (let i = first; i <= top; i++) tiers.push(tierAt(i, rocketSpeed, resistance, i === top));
	return tiers;
}
