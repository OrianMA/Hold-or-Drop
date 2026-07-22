-- Compiled with roblox-ts v3.0.0
-- ── Rocket gameplay tuning ──────────────────────────────────────────────────────
-- Shared so server (game logic) and client (effects) agree on timing.
-- Seconds over which the explosion risk ramps to its max and the progress bar
-- fills. Defines the full length of the risk curve.
local RISK_RAMP_DURATION = 17
-- Seconds between each multiplier tick.
local MULTIPLIER_TICK_RATE = 1
-- Value the in-game multiplier starts at (1 = base payout before any growth).
local STARTING_MULTIPLIER = 1
-- The payout multiplier tracks the rocket's LIVE velocity: each multiplier tick
-- adds `velocity × MULTIPLIER_TICK_RATE × MULTIPLIER_PER_STUD` (i.e. it grows by
-- the distance the rocket just climbed). Velocity starts at 0 and accelerates, so
-- the multiplier is near-frozen at liftoff and ramps hard once the rocket is fast.
-- A higher Rocket Speed stat raises the velocity, so it speeds up the multiplier
-- and the rocket together.
local MULTIPLIER_PER_STUD = 0.01
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
-- de Rocket Speed ("×6.0 à 10 s"). 10 s = le moment où la fusée atteint sa vitesse max.
local SPEED_PREVIEW_SECONDS = 10
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
return {
	multiplierAfter = multiplierAfter,
	RISK_RAMP_DURATION = RISK_RAMP_DURATION,
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
}
