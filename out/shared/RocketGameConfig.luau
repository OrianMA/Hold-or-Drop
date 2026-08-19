-- Compiled with roblox-ts v3.0.0
-- ── Rocket gameplay tuning ──────────────────────────────────────────────────────
-- Shared so server (game logic) and client (effects) agree on timing.
-- Secondes entre deux ticks de multiplicateur. Les vols durent ~7 s en moyenne
-- (voir rollExplosionTime) : à 0.25 s le multiplicateur suit la durée réelle du vol
-- de près, au lieu de sauter d'un cran entier pour 0.1 s de vol en plus ou en moins.
local MULTIPLIER_TICK_RATE = 0.25
-- Value the in-game multiplier starts at (1 = base payout before any growth).
local STARTING_MULTIPLIER = 1
-- The payout multiplier tracks the rocket's LIVE velocity: each multiplier tick
-- adds `velocity × MULTIPLIER_TICK_RATE × MULTIPLIER_PER_STUD` (i.e. it grows by
-- the distance the rocket just climbed). Velocity starts at 0 and accelerates, so
-- the multiplier is near-frozen at liftoff and ramps hard once the rocket is fast.
-- A higher Rocket Speed stat raises the velocity, so it speeds up the multiplier
-- and the rocket together.
-- Calibré sur la durée de vol moyenne à Resistance 0 (7 s) pour un multiplicateur
-- moyen de ×1.50 : 5 s → ×1.24, 7 s → ×1.46, 10 s → ×1.94, 15 s → ×2.85.
local MULTIPLIER_PER_STUD = 0.0061
-- ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
-- La fusée monte pendant le vol : la vitesse part de 0, monte de ROCKET_ACCEL
-- (studs/s²) jusqu'à ROCKET_MAX_SPEED (studs/s), puis reste constante.
-- Ces valeurs sont PAR UNITÉ DE ROCKET SPEED : launch() les multiplie par la stat du
-- joueur. Au niveau 0 (valeur 1) la fusée atteint 30 studs/s en 10 s — assez pour que
-- le multiplicateur bouge visiblement dès le premier run. Chaque niveau ajoute une
-- unité entière, donc le premier achat double littéralement la vitesse ET la vitesse
-- de montée du multiplicateur.
local ROCKET_ACCEL = 3
local ROCKET_MAX_SPEED = 30
-- ── Rocket steering (RocketLauncher) ────────────────────────────────────────────
-- In flight the rocket moves along its OWN up-axis. The player's native left/right
-- movement input (keyboard A/D, mobile thumbstick, gamepad stick — the character is
-- anchored so it doesn't walk, RocketSteerController) rolls the rocket left/right,
-- tilting its up-axis so it drifts sideways. The roll rate is near-zero at liftoff
-- and ramps to full once the rocket reaches "space" (STEER_SPACE_HEIGHT studs above
-- the pad), so it stays centred in the room shaft early and only becomes steerable in
-- open sky. The roll is UNCAPPED — it accumulates freely — and the rocket keeps
-- whatever tilt it has when input is released (no auto-centre). The payout multiplier
-- reads only the scalar velocity, so steering never affects it.
local STEER_ROT_SPEED_GROUND = math.rad(4)
local STEER_ROT_SPEED_SPACE = math.rad(30)
local STEER_SPACE_HEIGHT = 50
-- Seconds the camera lingers on the exploding rocket (loss) before swinging back
-- to the player. Shared so the server reset and the client camera restore agree.
local EXPLOSION_VIEW_DELAY = 1.5
-- Nombre de secondes de vol utilisé par le shop pour prévisualiser l'effet d'un niveau
-- de Rocket Speed ("×1.5 à 7 s"). 7 s = la durée de vol moyenne à Resistance 0.
local SPEED_PREVIEW_SECONDS = 7
-- Multiplicateur atteint après `seconds` de vol pour une valeur de Rocket Speed donnée.
-- Reproduit exactement la boucle serveur (un tick toutes les MULTIPLIER_TICK_RATE
-- secondes, chaque tick ajoute vitesse × tick × MULTIPLIER_PER_STUD). Pure — utilisée
-- par le shop côté client pour montrer ce qu'achète un niveau.
local function multiplierAfter(speedValue, seconds)
	local accel = ROCKET_ACCEL * speedValue
	local maxSpeed = ROCKET_MAX_SPEED * speedValue
	local mult = STARTING_MULTIPLIER
	do
		local t = MULTIPLIER_TICK_RATE
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				t += MULTIPLIER_TICK_RATE
			else
				_shouldIncrement = true
			end
			if not (t <= seconds + 1e-6) then
				break
			end
			mult += math.min(accel * t, maxSpeed) * MULTIPLIER_TICK_RATE * MULTIPLIER_PER_STUD
		end
	end
	return mult
end
-- ── Perfect Claim ───────────────────────────────────────────────────────────────
-- Claim juste AVANT que la fusée explose = "Perfect Claim" : le BASE CASH verrouillé est
-- multiplié par PERFECT_CLAIM_MULTIPLIER (le multiplicateur, lui, ne bouge pas — le gain
-- final est le même, mais le joueur voit quelle valeur a grossi). La fenêtre vaut PERFECT_CLAIM_WINDOW
-- secondes sur un vol court ; au-delà de PERFECT_CLAIM_REFERENCE_TIME secondes de vol
-- elle s'élargit proportionnellement (sinon un vol long — donc plus imprévisible —
-- exigerait un timing bien plus dur qu'un vol court), plafonnée à
-- PERFECT_CLAIM_MAX_WINDOW pour que ça reste un coup de timing.
--   vol 7s ou moins → 0.50 s   |   vol 14s → 1.00 s   |   vol 21s et plus → 1.50 s
local PERFECT_CLAIM_MULTIPLIER = 3
local PERFECT_CLAIM_WINDOW = 0.5
local PERFECT_CLAIM_REFERENCE_TIME = 7
local PERFECT_CLAIM_MAX_WINDOW = 1.5
-- Fenêtre de Perfect Claim (secondes avant l'explosion) pour un vol qui dure
-- `explosionTime` secondes. Pure — serveur (validation) et client (affichage).
local function perfectClaimWindow(explosionTime)
	if explosionTime <= PERFECT_CLAIM_REFERENCE_TIME then
		return PERFECT_CLAIM_WINDOW
	end
	local scaled = PERFECT_CLAIM_WINDOW * (explosionTime / PERFECT_CLAIM_REFERENCE_TIME)
	return math.min(scaled, PERFECT_CLAIM_MAX_WINDOW)
end
-- ── Critical Claim ──────────────────────────────────────────────────────────────
-- Chaque claim tire un dé : CRITICAL_CLAIM_CHANCE de chance que le BASE CASH verrouillé soit
-- multiplié par CRITICAL_CLAIM_MULTIPLIER. Rien à jouer, aucun timing — c'est la surprise
-- pure, annoncée au claim par le flash doré (client/ui/ClaimFlashText). Cumulable avec le
-- Perfect Claim : les deux facteurs se multiplient (×3 × ×10 = ×30).
local CRITICAL_CLAIM_CHANCE = 0.05
local CRITICAL_CLAIM_MULTIPLIER = 10
return {
	multiplierAfter = multiplierAfter,
	perfectClaimWindow = perfectClaimWindow,
	MULTIPLIER_TICK_RATE = MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER = STARTING_MULTIPLIER,
	MULTIPLIER_PER_STUD = MULTIPLIER_PER_STUD,
	ROCKET_ACCEL = ROCKET_ACCEL,
	ROCKET_MAX_SPEED = ROCKET_MAX_SPEED,
	STEER_ROT_SPEED_GROUND = STEER_ROT_SPEED_GROUND,
	STEER_ROT_SPEED_SPACE = STEER_ROT_SPEED_SPACE,
	STEER_SPACE_HEIGHT = STEER_SPACE_HEIGHT,
	EXPLOSION_VIEW_DELAY = EXPLOSION_VIEW_DELAY,
	SPEED_PREVIEW_SECONDS = SPEED_PREVIEW_SECONDS,
	PERFECT_CLAIM_MULTIPLIER = PERFECT_CLAIM_MULTIPLIER,
	PERFECT_CLAIM_WINDOW = PERFECT_CLAIM_WINDOW,
	PERFECT_CLAIM_REFERENCE_TIME = PERFECT_CLAIM_REFERENCE_TIME,
	PERFECT_CLAIM_MAX_WINDOW = PERFECT_CLAIM_MAX_WINDOW,
	CRITICAL_CLAIM_CHANCE = CRITICAL_CLAIM_CHANCE,
	CRITICAL_CLAIM_MULTIPLIER = CRITICAL_CLAIM_MULTIPLIER,
}
