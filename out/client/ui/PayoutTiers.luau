-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
-- ── Paliers de paiement (écran de fin) ─────────────────────────────────────────
--
-- Décrit l'ESCALADE de l'animation de paiement : plus le run est gros, plus le son est
-- fort et aigu, plus il y a de billets. Consommé par EndGameAnimation (§6.4), qui
-- déclenche un palier chaque fois que le compteur franchit son seuil pendant le count-up.
--
-- ── Pourquoi des CENTILES et pas des multiplicateurs fixes ────────────────────
-- Le multiplicateur atteint dépend de DEUX stats : la Rocket Speed (linéaire —
-- `mult = 1 + rocketSpeed × G(durée)`) et la Resistance (qui allonge la durée de vol).
-- Une échelle de seuils fixes (×2/×10/×100) serait donc inatteignable en early et
-- saturée en late : l'animation redeviendrait identique à chaque run.
--
-- Un ratio à la moyenne (`mult / moyenne`) ne suffit pas non plus : la `safeWindow` de
-- la Resistance est DÉTERMINISTE, donc elle écrase la variance relative. À Resistance 0
-- le meilleur centile vaut ~3.9× la moyenne, à Resistance 100 seulement ~1.5× — un
-- palier "≥ 2.5× ta moyenne" deviendrait inatteignable en fin de progression, et
-- acheter de la Resistance rendrait les paiements MOINS spectaculaires.
--
-- La réponse : chaque palier est un CENTILE de la propre distribution de vol du joueur.
-- "Ce run bat 90 % de tes runs" veut dire la même chose à toute Rocket Speed et à toute
-- Resistance — l'escalade est donc calibrée en permanence. Et c'est analytique, pas
-- simulé : la durée de vol au centile p est `safeWindow + médiane × e^(σ·z_p)`
-- (shared/ResistanceCurve.flightTimeAtZ), qu'on repasse dans `multiplierAfter`.
--
-- Rien n'affiche jamais le seuil au joueur — les paliers ne pilotent que le son et les
-- particules — donc on ne perd aucune lisibilité en abandonnant les nombres ronds.
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local multiplierAfter = _RocketGameConfig.multiplierAfter
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local flightTimeAtZ = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ResistanceCurve").flightTimeAtZ
-- Quantiles de la loi normale centrée réduite pour les centiles visés. Le palier i se
-- déclenche quand le run bat TIER_PERCENTILES[i] de ses runs.
--   z ≈  -0.385 / 0.253 / 0.772 / 1.282 / 1.751 / 2.326 / 2.748 / 3.291
local TIER_PERCENTILE_Z = { -0.3853, 0.2533, 0.7722, 1.2816, 1.7507, 2.3263, 2.7478, 3.2905 }
-- Nombre de paliers effectivement joués : les plus hauts franchis. Au-delà de 3
-- l'escalade s'étale trop et le count-up (plafonné à ~1.2 s) part en bouillie.
local MAX_PLAYED = 3
-- Le palier 0 n'a pas de centile : il est TOUJOURS franchi (seuil = multiplicateur de
-- départ). Tout paiement déclenche donc au moins un son et une pluie légère.
local TIER_COUNT = #TIER_PERCENTILE_Z + 1
local LAST_INDEX = TIER_COUNT - 1
-- À partir de cet index, le palier ajoute le son "gros lot" (centile 90 → top 10 %).
local BIG_REWARD_INDEX = 4
-- À partir de cet index, des lingots d'or tombent avec les billets (centile 78).
local GOLD_RAIN_INDEX = 3
-- Le CLIMAX d'une escalade qui atteint cet index (centile 96 → top 4 %) déclenche le
-- DÉLUGE de lingots : la pluie de billets est remplacée par une pluie d'or dense.
local INGOT_DOWNPOUR_INDEX = 5
-- ── Bornes d'intensité ─────────────────────────────────────────────────────────
-- Tout est interpolé linéairement de l'index 0 au dernier index, plutôt qu'écrit
-- palier par palier : la monotonie est garantie et le tuning tient en deux valeurs.
local PITCH_MIN = 1
local PITCH_MAX = 1.3
local VOLUME_MIN = 0.5
local VOLUME_MAX = 1
local BURST_MIN = 6
local BURST_MAX = 36
-- Dépassement du UIScale au déclenchement du palier. C'est le "punch" du montant.
-- Il passe par un UIScale et NON par TextSize : Roblox plafonne TextSize à 100, et
-- BaseCashText démarre déjà à 85 — un dépassement sur la taille serait donc écrêté,
-- pile sur les gros paliers. UIScale n'a pas cette limite.
local PUNCH_MIN = 1.12
local PUNCH_MAX = 1.4
local RAIN_MIN = 8
-- Le palier max demande RAIN_MAX billets + RAIN_MAX / 2 en lingots, soit ~55 gouttes :
-- ça doit tenir sous MAX_LIVE_DROPS (CriticalRain) pour que le plus gros palier
-- s'affiche en entier sans avoir à évincer sa propre pluie d'or.
local RAIN_MAX = 40
-- Déluge de lingots du climax. Il REMPLACE la pluie de billets sur ce palier — une
-- pluie d'or pure se lit mieux qu'un mélange, et ça tient sous le plafond de gouttes.
local INGOT_DOWNPOUR_MIN = 40
local INGOT_DOWNPOUR_MAX = 62
-- Rouge clair (couleur historique du count-up) → or plein.
local COLOR_MIN = Color3.fromRGB(255, 64, 64)
local COLOR_MAX = Color3.fromRGB(255, 200, 60)
local function lerp(from, to, t)
	return from + (to - from) * t
end
-- Multiplicateur que ce joueur atteint au centile `z` de ses vols. C'est le seuil du
-- palier : il suit automatiquement la Rocket Speed ET la Resistance.
local function thresholdAt(index, rocketSpeed, resistance)
	if index == 0 then
		return STARTING_MULTIPLIER
	end
	return multiplierAfter(rocketSpeed, flightTimeAtZ(resistance, TIER_PERCENTILE_Z[index]))
end
local function tierAt(index, rocketSpeed, resistance, isClimax)
	local t = if LAST_INDEX > 0 then index / LAST_INDEX else 0
	local downpour = isClimax and index >= INGOT_DOWNPOUR_INDEX
	return {
		index = index,
		threshold = thresholdAt(index, rocketSpeed, resistance),
		pitch = lerp(PITCH_MIN, PITCH_MAX, t),
		volume = lerp(VOLUME_MIN, VOLUME_MAX, t),
		burstCount = math.floor(lerp(BURST_MIN, BURST_MAX, t) + 0.5),
		rainCount = math.floor(lerp(RAIN_MIN, RAIN_MAX, t) + 0.5),
		color = COLOR_MIN:Lerp(COLOR_MAX, t),
		punch = lerp(PUNCH_MIN, PUNCH_MAX, t),
		goldRain = not downpour and index >= GOLD_RAIN_INDEX,
		bigReward = index >= BIG_REWARD_INDEX,
		ingotDownpour = if downpour then math.floor(lerp(INGOT_DOWNPOUR_MIN, INGOT_DOWNPOUR_MAX, t) + 0.5) else 0,
	}
end
-- Rang du plus haut palier franchi (0 au minimum — le palier 0 l'est toujours). Sert à
-- doser ce qui dépend de l'ampleur globale sans rejouer l'escalade (nombre de liasses,
-- gerbe finale).
local function topTierIndex(multiplier, rocketSpeed, resistance)
	local top = 0
	do
		local i = 1
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < TIER_COUNT) then
				break
			end
			if multiplier >= thresholdAt(i, rocketSpeed, resistance) then
				top = i
			end
		end
	end
	return top
end
-- Paliers à JOUER, du plus bas au plus haut : les MAX_PLAYED derniers franchis.
local function tiersCrossed(multiplier, rocketSpeed, resistance)
	local top = topTierIndex(multiplier, rocketSpeed, resistance)
	local first = math.max(0, top - MAX_PLAYED + 1)
	local tiers = {}
	do
		local i = first
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i <= top) then
				break
			end
			local _arg0 = tierAt(i, rocketSpeed, resistance, i == top)
			table.insert(tiers, _arg0)
		end
	end
	return tiers
end
return {
	topTierIndex = topTierIndex,
	tiersCrossed = tiersCrossed,
}
