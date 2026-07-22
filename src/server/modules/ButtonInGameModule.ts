import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";
import { PlayerProgressionService } from "server/services/PlayerProgressionService";
import { ReplicatedStorage, Workspace } from "@rbxts/services";
import { invincible } from "server/modules/CheatConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";
import { RocketLauncher } from "server/modules/RocketLauncher";
import { RocketPlacer } from "server/modules/RocketPlacer";
import {
	RISK_RAMP_DURATION,
	MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER,
	MULTIPLIER_PER_STUD,
	EXPLOSION_VIEW_DELAY,
} from "shared/RocketGameConfig";
import { AudioConfig } from "shared/AudioConfig";

// ── Game tuning ───────────────────────────────────────────────────────────────

const MAX_RISK = 0.8;
const TICK_RATE = 0.5;
// Lot de consolation sur une perte (explosion sans claim) : baseCash / 3 —
// FORFAITAIRE, sans le multiplicateur. Pas de popup de fin.
const LOSS_CONSOLATION_DIVISOR = 3;
// "Go Home" (retour à la base après un claim) : délai avant de reposer le rig sur le pad,
// le temps que la caméra soit revenue au joueur.
const GO_HOME_RESET_DELAY = 0.6;

const EXPLOSION_SOUND_ID = AudioConfig.sfx.explosion.id;
const EXPLOSION_SOUND_VOLUME = AudioConfig.sfx.explosion.volume;
const EXPLOSION_SOUND_ROLLOFF = 120; // détail 3D propre au serveur

// Alias — keeps the risk/progress math unchanged while sourcing the value from the shared config
const TOTAL_DURATION = RISK_RAMP_DURATION;

// ── Sound preloading ──────────────────────────────────────────────────────────
// A template Sound in ReplicatedStorage replicates to all clients on join,
// causing them to pre-buffer the audio asset before any explosion fires.
// Cloning a pre-buffered template eliminates the CDN fetch delay at runtime.

const assetsFolder = (() => {
	const existing = ReplicatedStorage.FindFirstChild("HoldOrDropAssets");
	if (existing !== undefined) return existing as Folder;
	const folder = new Instance("Folder");
	folder.Name = "HoldOrDropAssets";
	folder.Parent = ReplicatedStorage;
	return folder;
})();

const explosionSoundTemplate = (() => {
	const sound = new Instance("Sound");
	sound.Name = "ExplosionSound";
	sound.SoundId = EXPLOSION_SOUND_ID;
	sound.Volume = EXPLOSION_SOUND_VOLUME;
	sound.RollOffMaxDistance = EXPLOSION_SOUND_ROLLOFF;
	sound.Parent = assetsFolder;
	return sound;
})();

// ── Helpers ───────────────────────────────────────────────────────────────────

// EaseInQuad: risk starts near 0 and accelerates — reaches MAX_RISK at TOTAL_DURATION seconds
function getRisk(timeHeld: number): number {
	const t = math.min(timeHeld / TOTAL_DURATION, 1);
	return MAX_RISK * (t * t);
}

// ── Resistance → risk model ──────────────────────────────────────────────────────
// Resistance is a 0..100 shop stat (see ShopConfig). It reshapes the explosion risk
// in two independent ways, so a higher resistance both lasts longer on average AND
// gets a longer guaranteed-safe head start:
//   • riskScale  — scales the WHOLE risk curve down. FRONT-loaded (reduction =
//     MAX_REDUCTION × (1 − (1 − n)^CURVE)): the first levels cut risk hugely, the
//     last levels barely move it. This is what makes level 20 already ~20s average.
//   • safeWindow — seconds at the start where risk is forced to 0. BACK-loaded
//     (n^CURVE × MAX): it stays ~0 until high resistance and only reaches ~15s near
//     level 100 — so a max rocket can't blow before ~15s, while a level-20 rocket
//     still has a very small early chance.
// After the safe window the base curve ramps from 0 (shifted by safeWindow), so the
// post-window climb is gentle. At resistance 0 both terms are neutral → identical to
// the un-upgraded curve.
const RESISTANCE_MAX_LEVEL = 100;
const RESISTANCE_MAX_REDUCTION = 0.99; // risk floored at ×0.01 at level 100
const RESISTANCE_REDUCTION_CURVE = 12; // ↑ = more front-loaded (early levels matter more)
const RESISTANCE_MAX_SAFE_WINDOW = 15; // seconds of guaranteed safety at level 100
const RESISTANCE_SAFE_WINDOW_CURVE = 2.5; // ↑ = window stays near 0 until higher levels

interface RiskParams {
	readonly riskScale: number;
	readonly safeWindow: number;
}

function resistanceRiskParams(resistance: number): RiskParams {
	const n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1);
	const reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ** RESISTANCE_REDUCTION_CURVE);
	const safeWindow = n ** RESISTANCE_SAFE_WINDOW_CURVE * RESISTANCE_MAX_SAFE_WINDOW;
	return { riskScale: 1 - reduction, safeWindow };
}

// Effective per-tick risk at `timeHeld` for a resistance profile. Zero inside the
// safe window; outside it the base curve ramps from the window's end, scaled down.
function riskAt(timeHeld: number, params: RiskParams): number {
	if (timeHeld <= params.safeWindow) return 0;
	return getRisk(timeHeld - params.safeWindow) * params.riskScale;
}

// ── Explosion-time preload ──────────────────────────────────────────────────────
// Guard on the precompute loop. At max resistance the risk floor is tiny and the
// safe window pushes the first roll to ~15s, so a run can last minutes — but never
// forever. 2000 ticks (1000s) only guards against a pathological never-ending loop;
// no real hold reaches it.
const EXPLOSION_ROLL_CAP = 2000;

// Precompute, once at launch, the exact moment the rocket will explode by running the
// SAME per-tick risk roll the live loop uses — but all at once, up front. This "loads"
// the explosion time so the run can fire the explosion at that precise scheduled moment
// instead of re-rolling RNG every tick and discovering it late (action/event delay).
// The probability distribution is identical to the live per-tick model. Returns the
// time-held (seconds, tick-aligned) at which the rocket explodes.
function rollExplosionTime(params: RiskParams): number {
	let timeHeld = 0;
	for (let i = 0; i < EXPLOSION_ROLL_CAP; i++) {
		timeHeld += TICK_RATE;
		if (math.random() < riskAt(timeHeld, params)) return timeHeld;
	}
	return timeHeld;
}

// Plays the 3D explosion boom at `pos` (heard by everyone). Cloned from the
// pre-buffered template — no CDN fetch on the client. Parented to Terrain via an
// Attachment for proper 3D rolloff.
function playExplosionSoundAt(pos: Vector3): void {
	const attachment = new Instance("Attachment");
	attachment.Parent = Workspace.Terrain;
	attachment.WorldPosition = pos;

	const sound = explosionSoundTemplate.Clone();
	sound.Parent = attachment;
	sound.Play();
	sound.Ended.Connect(() => attachment.Destroy());
}

// ── Public API ────────────────────────────────────────────────────────────────

// Used by the ButtonMenu Quit flow — release/explosion endings transition
// through EndGameButtonModule.enter() instead, which performs the same cleanup.
// Native left/right movement redirected to the flying rocket. The client sends the
// quantised steering intent (-1/0/+1) only when it changes; we resolve the player's
// active room and forward it. setSteer is a no-op when the room isn't flying, so input
// outside a run is harmless — no per-game connection to manage. Registered once on load.
Events.RocketSteerEvent.OnServerEvent.Connect((player, dir) => {
	const session = ButtonSessionService.getSession(player);
	if (!session) return;
	RocketLauncher.setSteer(session.room, typeIs(dir, "number") ? dir : 0);
});

export function endButtonGame(player: Player): void {
	ButtonSessionService.cleanup(player);
	UiService.HideCurrent(player);
}

export function startButtonGame(player: Player, session: ButtonSession): void {
	const room = session.room;

	// EffectiveBaseCash already folds in every money multiplier (rebirth + money
	// game-pass tier + community), additively. Read once — held for the session so
	// a mid-run boost change can't alter an in-progress hold.
	const baseCash = PlayerProgressionService.get(player, "EffectiveBaseCash");

	// Resistance (0..100, incl. the pass) reshapes the explosion risk — see
	// resistanceRiskParams. Read once and resolved to its risk profile for the run.
	const resistance = PlayerProgressionService.get(player, "Resistance");
	const riskParams = resistanceRiskParams(resistance);

	// Rocket Speed stat value (≥1) scales the rocket's ascent. Read once for the run.
	const rocketSpeed = PlayerProgressionService.get(player, "RocketSpeed");

	// Démarre à 1.00x puis grimpe au rythme de la vitesse RÉELLE de la fusée : tant
	// qu'elle est lente (Rocket Speed bas), le multiplicateur bouge à peine ; plus la
	// fusée va vite, plus il grimpe (voir RocketGameConfig).
	let currentMultiplier = STARTING_MULTIPLIER;
	let isActive = true;

	// Preload the "chance" at launch: precompute the exact instant the rocket will
	// explode (tick-aligned, same distribution as the old per-tick roll). The run then
	// fires the explosion at this scheduled moment — no per-tick RNG, no discovery delay.
	// invincible ⇒ never explodes.
	const explosionAt = invincible ? math.huge : rollExplosionTime(riskParams);

	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
	Events.RiskUpdateEvent.FireClient(player, 0);

	// La fusée décolle dès le début du gameplay, à une vitesse pilotée par le stat
	// Rocket Speed du joueur (1 = rampe). Sa vélocité pilote ensuite le multiplicateur.
	RocketLauncher.launch(room, rocketSpeed);

	// Claim : le joueur VERROUILLE le multiplicateur courant en gain garanti. La fusée ne
	// s'arrête PAS — elle continue de monter (le multiplicateur affiché grimpe encore,
	// purement visuel) jusqu'à l'explosion, où le payout se fait au multiplicateur
	// verrouillé EXACT (voir la boucle risque plus bas). Remplace l'ancien "release".
	let claimed = false;
	let claimedMultiplier = STARTING_MULTIPLIER;
	const claimConn = Events.ClaimButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive || claimed) return;
		claimed = true;
		claimedMultiplier = currentMultiplier; // valeur autoritative exacte au moment du claim
		Events.ClaimAcceptedEvent.FireClient(player, claimedMultiplier);
	});

	// "Go Home" : après un claim, le joueur peut rentrer à la base sans attendre
	// l'explosion. La fusée s'arrête net et le gain VERROUILLÉ est payé exactement comme
	// après une explosion post-claim — simplement sans explosion. Refusé tant qu'on n'a
	// pas claim (sinon ce serait une sortie gratuite du risque).
	const goHomeConn = Events.GoHomeEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive || !claimed) return;
		isActive = false;
		claimConn.Disconnect();
		goHomeConn.Disconnect();

		RocketLauncher.stop(room); // la fusée s'arrête sur place (moteur + son coupés)

		const earned = math.floor(baseCash * claimedMultiplier);
		// exploded=false : c'est le client qui ramène la caméra au joueur (retour à la base).
		Events.GameResultEvent.FireClient(player, false, earned, claimedMultiplier);
		EndGameButtonModule.enter(player, "released", baseCash, claimedMultiplier, earned, 1);

		// On laisse la caméra revenir au joueur avant de reposer le rig sur le pad
		// (sinon la fusée se téléporterait sous les yeux du joueur), puis la fusée est
		// réinstanciée neuve sur le pad — exactement comme après une explosion.
		task.delay(GO_HOME_RESET_DELAY, () => {
			RocketLauncher.reset(room); // ramène le rig (caméra/particules) sur le pad
			RocketPlacer.place(room); // fusée neuve sur le pad, comme après une explosion
		});
	});

	// ── Boucle multiplier ─────────────────────────────────────────────────────
	// Le multiplicateur suit la vitesse RÉELLE de la fusée : chaque tick on ajoute
	// `vélocité × tick × MULTIPLIER_PER_STUD` (= la distance que la fusée vient de
	// monter). La vélocité part de 0 et accélère, donc le multiplicateur est quasi
	// figé au décollage puis grimpe d'autant plus vite que la fusée va vite (Rocket
	// Speed élevé). Indépendant de la boucle risque.
	task.spawn(() => {
		while (isActive) {
			task.wait(MULTIPLIER_TICK_RATE);
			if (!isActive) break;

			const climbed = RocketLauncher.getVelocity(room) * MULTIPLIER_TICK_RATE;
			currentMultiplier += climbed * MULTIPLIER_PER_STUD;
			Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
		}
	});

	// ── Boucle risque / explosion planifiée ──────────────────────────────────────
	// Rafraîchit la barre de risque à TICK_RATE et déclenche l'explosion à l'instant
	// `explosionAt` précalculé au décollage — plus aucun tirage aléatoire par tick.
	task.spawn(() => {
		let timeHeld = 0;

		while (isActive) {
			// Avance jusqu'au prochain rafraîchissement de barre sans jamais dépasser
			// l'instant d'explosion précalculé → l'explosion tombe pile à `explosionAt`.
			const nextStep = math.min(timeHeld + TICK_RATE, explosionAt);
			task.wait(nextStep - timeHeld);
			if (!isActive) break;

			timeHeld = nextStep;

			// Resistance reshapes the effective risk (scale + safe window) — same
			// profile used to precompute explosionAt, so the bar matches the outcome.
			const risk = riskAt(timeHeld, riskParams);
			Events.RiskUpdateEvent.FireClient(player, risk);

			if (!invincible && timeHeld >= explosionAt) {
				isActive = false;
				claimConn.Disconnect();
				goHomeConn.Disconnect(); // la fusée explose : plus de retour à la base possible

				if (claimed) {
					// Le joueur a claim avant l'explosion → gain GARANTI au multiplicateur
					// verrouillé. La fusée explose (spectacle), puis le payout se fait au
					// claimedMultiplier EXACT, sans aucune pénalité.
					const rocketPos = room.movableModel.GetPivot().Position;
					RocketLauncher.explode(room);
					playExplosionSoundAt(rocketPos); // boom 3D entendu par tous

					// Le client garde la caméra orbitale sur la fusée qui explose, puis revient.
					Events.PlayerKilledEvent.FireClient(player);

					task.wait(EXPLOSION_VIEW_DELAY);
					RocketLauncher.reset(room); // ramène le rig (caméra/particules) sur le pad
					RocketPlacer.place(room); // la fusée détruite est remplacée par une neuve

					const earned = math.floor(baseCash * claimedMultiplier);
					// exploded=true : côté client PlayerKilledEvent gère la caméra (pas de double retour).
					Events.GameResultEvent.FireClient(player, true, earned, claimedMultiplier);
					EndGameButtonModule.enter(player, "killed", baseCash, claimedMultiplier, earned, 1);
					return;
				}

				// Pas de claim à temps : perte sèche. La FUSÉE explose, pas le joueur —
				// pas de fling, pas de mort. explode() stoppe lui-même l'ascension après
				// avoir capturé sa vitesse, pour que les débris conservent l'élan vers le
				// haut (la fusée continue de monter en explosant) avant que la gravité ne
				// les rattrape.
				Events.ButtonExplodedEvent.FireClient(player);

				// Deregister button immediately (avoids WaitForChild blocking the UI)
				ButtonSessionService.cleanup(player);

				{
					const rocketPos = room.movableModel.GetPivot().Position;
					RocketLauncher.explode(room); // unanchor + burst, hérite de l'élan de montée
					playExplosionSoundAt(rocketPos); // boom 3D entendu par tous

					// Le client garde la caméra orbitale sur la fusée qui explose, puis revient.
					Events.PlayerKilledEvent.FireClient(player);

					// On laisse l'explosion se jouer avant de ramener le rig.
					task.wait(EXPLOSION_VIEW_DELAY);
					RocketLauncher.reset(room); // ramène le rig (caméra/particules) sur le pad
					RocketPlacer.place(room); // la fusée détruite est remplacée par une neuve

					// Perte : PAS de popup de fin. Lot de consolation forfaitaire
					// (baseCash / 3, sans le multiplicateur) montré par un seul texte qui
					// saute puis file vers l'argent du HUD (client LossRewardBehavior).
					const reward = math.floor(baseCash / LOSS_CONSOLATION_DIVISOR);
					Events.GameResultEvent.FireClient(player, true, reward, currentMultiplier);
					EndGameButtonModule.enterRewardOnly(player, reward);
				}
				return;
			}
		}
	});
}
