// ── Rocket gameplay tuning ──────────────────────────────────────────────────────
// Shared so server (game logic) and client (effects) agree on timing.

// Secondes entre deux ticks de multiplicateur. Les vols durent ~7 s en moyenne
// (voir rollExplosionTime) : à 0.25 s le multiplicateur suit la durée réelle du vol
// de près, au lieu de sauter d'un cran entier pour 0.1 s de vol en plus ou en moins.
export const MULTIPLIER_TICK_RATE = 0.25;

// Value the in-game multiplier starts at (1 = base payout before any growth).
export const STARTING_MULTIPLIER = 1;

// The payout multiplier tracks the rocket's LIVE velocity: each multiplier tick
// adds `velocity × MULTIPLIER_TICK_RATE × MULTIPLIER_PER_STUD` (i.e. it grows by
// the distance the rocket just climbed). Velocity starts at 0 and accelerates, so
// the multiplier is near-frozen at liftoff and ramps hard once the rocket is fast.
// A higher Rocket Speed stat raises the velocity, so it speeds up the multiplier
// and the rocket together.
// Calibré sur la durée de vol moyenne à Resistance 0 (7 s) pour un multiplicateur
// moyen de ×1.50 : 5 s → ×1.24, 7 s → ×1.46, 10 s → ×1.94, 15 s → ×2.85.
export const MULTIPLIER_PER_STUD = 0.0061;

// ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
// La fusée monte pendant le vol : la vitesse part de 0, monte de ROCKET_ACCEL
// (studs/s²) jusqu'à ROCKET_MAX_SPEED (studs/s), puis reste constante.
// Ces valeurs sont PAR UNITÉ DE ROCKET SPEED : launch() les multiplie par la stat du
// joueur. Au niveau 0 (valeur 1) la fusée atteint 30 studs/s en 10 s — assez pour que
// le multiplicateur bouge visiblement dès le premier run. Chaque niveau ajoute une
// unité entière, donc le premier achat double littéralement la vitesse ET la vitesse
// de montée du multiplicateur.
export const ROCKET_ACCEL = 3;
export const ROCKET_MAX_SPEED = 30;

// ── Rocket steering (RocketLauncher) ────────────────────────────────────────────
// In flight the rocket moves along its OWN up-axis. The player's native left/right
// movement input (keyboard A/D, mobile thumbstick, gamepad stick — the character is
// anchored so it doesn't walk, RocketSteerController) rolls the rocket left/right,
// tilting its up-axis so it drifts sideways. The roll rate is near-zero at liftoff
// and ramps to full once the rocket reaches "space" (STEER_SPACE_HEIGHT studs above
// the pad), so it stays centred in the room shaft early and only becomes steerable in
// open sky. The roll is UNCAPPED — it accumulates freely — and the rocket keeps
// whatever tilt it has when input is released (no auto-centre). The payout multiplier
// reads only the scalar velocity, so steering never affects it.
export const STEER_ROT_SPEED_GROUND = math.rad(4); // roll rate at the pad (rad/s) — extremely weak
export const STEER_ROT_SPEED_SPACE = math.rad(30); // roll rate in space (rad/s) — responsive
export const STEER_SPACE_HEIGHT = 50; // studs above the pad where roll authority reaches full

// Seconds the camera lingers on the exploding rocket (loss) before swinging back
// to the player. Shared so the server reset and the client camera restore agree.
export const EXPLOSION_VIEW_DELAY = 1.5;

// Nombre de secondes de vol utilisé par le shop pour prévisualiser l'effet d'un niveau
// de Rocket Speed ("×1.5 à 7 s"). 7 s = la durée de vol moyenne à Resistance 0.
export const SPEED_PREVIEW_SECONDS = 7;

// Multiplicateur atteint après `seconds` de vol pour une valeur de Rocket Speed donnée.
// Reproduit exactement la boucle serveur (un tick toutes les MULTIPLIER_TICK_RATE
// secondes, chaque tick ajoute vitesse × tick × MULTIPLIER_PER_STUD). Pure — utilisée
// par le shop côté client pour montrer ce qu'achète un niveau.
export function multiplierAfter(speedValue: number, seconds: number): number {
	const accel = ROCKET_ACCEL * speedValue;
	const maxSpeed = ROCKET_MAX_SPEED * speedValue;
	let mult = STARTING_MULTIPLIER;
	for (let t = MULTIPLIER_TICK_RATE; t <= seconds + 1e-6; t += MULTIPLIER_TICK_RATE) {
		mult += math.min(accel * t, maxSpeed) * MULTIPLIER_TICK_RATE * MULTIPLIER_PER_STUD;
	}
	return mult;
}

// ── Perfect Claim ───────────────────────────────────────────────────────────────
// Claim juste AVANT que la fusée explose = "Perfect Claim" : le BASE CASH verrouillé est
// multiplié par PERFECT_CLAIM_MULTIPLIER (le multiplicateur, lui, ne bouge pas — le gain
// final est le même, mais le joueur voit quelle valeur a grossi). La fenêtre vaut PERFECT_CLAIM_WINDOW
// secondes sur un vol court ; au-delà de PERFECT_CLAIM_REFERENCE_TIME secondes de vol
// elle s'élargit proportionnellement (sinon un vol long — donc plus imprévisible —
// exigerait un timing bien plus dur qu'un vol court), plafonnée à
// PERFECT_CLAIM_MAX_WINDOW pour que ça reste un coup de timing.
//   vol 7s ou moins → 0.75 s   |   vol 14s et plus → 1.50 s (plafond)
// S'ajoute par-dessus (hors plafond) un bonus fixe PERFECT_CLAIM_HIGH_MULT_BONUS dès que le
// multiplicateur dépasse PERFECT_CLAIM_HIGH_MULT : à ce stade la fusée file et le joueur a
// beaucoup à perdre, la zone s'élargit donc légèrement.
//   ×7 ou moins → 0.75 s sur un vol court   |   au-delà de ×7 → 1.00 s
export const PERFECT_CLAIM_MULTIPLIER = 3;
export const PERFECT_CLAIM_WINDOW = 0.75;
export const PERFECT_CLAIM_REFERENCE_TIME = 7;
export const PERFECT_CLAIM_MAX_WINDOW = 1.5;
export const PERFECT_CLAIM_HIGH_MULT = 7;
export const PERFECT_CLAIM_HIGH_MULT_BONUS = 0.25;

// Fenêtre de Perfect Claim (secondes avant l'explosion) pour un vol qui dure
// `explosionTime` secondes et claimé à `multiplier`. Pure — serveur (validation) et
// client (affichage).
export function perfectClaimWindow(explosionTime: number, multiplier: number): number {
	let seconds = PERFECT_CLAIM_WINDOW;
	if (explosionTime > PERFECT_CLAIM_REFERENCE_TIME) {
		const scaled = PERFECT_CLAIM_WINDOW * (explosionTime / PERFECT_CLAIM_REFERENCE_TIME);
		seconds = math.min(scaled, PERFECT_CLAIM_MAX_WINDOW);
	}
	if (multiplier > PERFECT_CLAIM_HIGH_MULT) seconds += PERFECT_CLAIM_HIGH_MULT_BONUS;
	return seconds;
}

// ── Critical Claim ──────────────────────────────────────────────────────────────
// Chaque claim tire un dé : CRITICAL_CLAIM_CHANCE de chance que le BASE CASH verrouillé soit
// multiplié par CRITICAL_CLAIM_MULTIPLIER. Rien à jouer, aucun timing — c'est la surprise
// pure, annoncée au claim par le flash doré (client/ui/ClaimFlashText). Cumulable avec le
// Perfect Claim : les deux facteurs se multiplient (×3 × ×10 = ×30).
export const CRITICAL_CLAIM_CHANCE = 0.12;
export const CRITICAL_CLAIM_MULTIPLIER = 10;
