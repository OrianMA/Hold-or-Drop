import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";
import { PlayerProgressionService } from "server/services/PlayerProgressionService";
import { ReplicatedStorage, Workspace } from "@rbxts/services";
import {
	boostCriticalClaim,
	boostedCriticalClaimChance,
	invincible,
	logExplosionForecast,
} from "server/modules/CheatConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";
import { AnalyticsService } from "server/services/AnalyticsService";
import { RocketLauncher } from "server/modules/RocketLauncher";
import { RocketPlacer } from "server/modules/RocketPlacer";
import { TutorialHooks } from "server/tutorial/TutorialHooks";
import {
	MULTIPLIER_TICK_RATE,
	STARTING_MULTIPLIER,
	MULTIPLIER_PER_STUD,
	EXPLOSION_VIEW_DELAY,
	PERFECT_CLAIM_MULTIPLIER,
	CRITICAL_CLAIM_CHANCE,
	CRITICAL_CLAIM_MULTIPLIER,
	perfectClaimWindow,
	multiplierAfter,
} from "shared/RocketGameConfig";
import { AudioConfig } from "shared/AudioConfig";
import { RiskParams, resistanceRiskParams } from "shared/ResistanceCurve";

// ── Game tuning ───────────────────────────────────────────────────────────────

const TICK_RATE = 0.5;
// Lot de consolation sur une perte (explosion sans claim) : baseCash / 3 —
// FORFAITAIRE, sans le multiplicateur. Pas de popup de fin.
const LOSS_CONSOLATION_DIVISOR = 3;
// "Go Home" (retour à la base après un claim) : délai avant de reposer le rig sur le pad,
// le temps que la caméra soit revenue au joueur.
const GO_HOME_RESET_DELAY = 0.6;

// ── Durée de vol : cloche de Gauss (log-normale) ─────────────────────────────
// La durée d'un vol est TIRÉE D'UN COUP au décollage dans une cloche de Gauss — pas
// accumulée dé après dé. Le tirage est gaussien sur une échelle MULTIPLICATIVE du
// temps ("4 s ×÷ 1.4") et non additive ("4 s ± 1.2 s") : la cloche a la même forme,
// même pic net et mêmes chances qui s'effondrent quand on s'éloigne, mais elle ne
// peut jamais produire une durée nulle ou négative — et son côté long reste libre de
// s'allonger, ce qui laisse exister le coup rare. Une cloche additive serait fermée
// des deux côtés : pour garder le bas au-dessus de zéro il faudrait serrer le haut,
// et le vol jackpot n'existerait plus.
//   • FLIGHT_TIME_MEAN  — durée MOYENNE d'un vol à Resistance 0.
//   • FLIGHT_TIME_SIGMA — largeur de la cloche. Seul bouton pour rendre le jeu plus
//     ou moins imprévisible ; il ne déplace pas la moyenne (la médiane est recalculée
//     pour compenser).
// Repères à Resistance 0 (μ = 4 s, σ = 0.35) : 68 % des vols entre 2.7 et 5.3 s,
// 95 % entre 1.9 et 7.5 s, ~0.25 % dépassent 10 s, plafond observé ~22 s. Côté gain :
// multiplicateur moyen ×1.52, un ×3 tous les ~100 runs, un ×5 tous les ~2 200.
const FLIGHT_TIME_MEAN = 4;
const FLIGHT_TIME_SIGMA = 0.35;

// Garde-fous du tirage : la cloche n'est pas bornée, on coupe les deux queues bien
// au-delà de ce qu'un joueur verra jamais.
const FLIGHT_TIME_MIN = 0.1;
const FLIGHT_TIME_MAX = 60;

// Médiane telle que la MOYENNE vaille FLIGHT_TIME_MEAN — sur une échelle
// multiplicative, moyenne = médiane × e^(σ²/2). Régler σ ne déplace donc pas la moyenne.
const FLIGHT_TIME_MEDIAN = FLIGHT_TIME_MEAN * math.exp(-(FLIGHT_TIME_SIGMA * FLIGHT_TIME_SIGMA) / 2);

const EXPLOSION_SOUND_ID = AudioConfig.sfx.explosion.id;
const EXPLOSION_SOUND_VOLUME = AudioConfig.sfx.explosion.volume;
const EXPLOSION_SOUND_ROLLOFF = 120; // détail 3D propre au serveur

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

// ── Explosion-time preload ──────────────────────────────────────────────────────
// Tire, une fois au décollage, l'instant EXACT où la fusée explosera. Le run déclenche
// ensuite l'explosion pile à l'heure, au lieu de relancer un dé à chaque tick et de la
// découvrir en retard. Résultat continu — aucun alignement sur un pas de temps.
//
// Le profil de Resistance déforme la cloche sans en changer les proportions :
//   • safeWindow — secondes garanties, AJOUTÉES au tirage. La promesse du shop
//     ("Vol garanti X s") est donc tenue littéralement, quoi que sorte le dé.
//   • riskScale  — multiplie la médiane par riskScale^(-1/3), l'étirement documenté
//     dans ResistanceCurve. Sur une échelle multiplicative, étirer la médiane étire
//     la cloche entière : elle garde exactement sa forme à tous les niveaux.
function rollExplosionTime(params: RiskParams): number {
	// Box–Muller : une normale centrée réduite à partir de deux uniformes.
	// 1 - math.random() ∈ (0,1] ⇒ jamais log(0).
	const gauss = math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random());

	const median = FLIGHT_TIME_MEDIAN * params.riskScale ** (-1 / 3);
	const flight = params.safeWindow + median * math.exp(FLIGHT_TIME_SIGMA * gauss);
	return math.clamp(flight, FLIGHT_TIME_MIN, FLIGHT_TIME_MAX);
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

// Cheat `logExplosionForecast` : imprime l'issue précalculée du vol. Le multiplicateur
// prévu est reconstruit par `multiplierAfter`, qui rejoue exactement la boucle
// multiplicateur (même tick, même vitesse) — c'est donc la valeur que le joueur verra à
// l'instant de l'explosion s'il ne claim pas avant.
function logForecast(player: Player, deadline: number, effectiveSpeed: number, baseCash: number): void {
	if (deadline === math.huge) {
		print(`[CHEAT] ${player.Name} — la fusée n'explosera pas (invincible / run scripté sans risque)`);
		return;
	}
	const predicted = multiplierAfter(effectiveSpeed, deadline);
	print(
		string.format(
			"[CHEAT] %s — explosion dans %.2fs | multiplicateur prévu ×%.2f (~$%d) | Perfect Claim si claim après %.2fs",
			player.Name,
			deadline,
			predicted,
			math.floor(baseCash * predicted),
			deadline - perfectClaimWindow(deadline),
		),
	);
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

	// EffectiveBaseCash already folds in every money multiplier (rebirth multiplies;
	// money game-pass tier + community add inside that boost factor — see
	// shared/ShopConfig.moneyMult). Read once — held for the session so a mid-run
	// boost change can't alter an in-progress hold.
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

	// Analytics: one funnel session id for this run (CoreRun: Launch → Claim → Banked).
	const runId = AnalyticsService.newRunId();

	// Preload the "chance" at launch: tire l'instant exact où la fusée explosera dans une
	// courbe de Gauss (voir rollExplosionTime). The run then fires the explosion at this
	// scheduled moment — no per-tick RNG, no discovery delay.
	// Tutorial : si le step courant impose un scénario (gel, explosion programmée), le
	// director le joue et fournit la deadline d'explosion — qu'il peut réécrire au claim.
	// undefined hors tutorial → comportement normal intégral.
	const scripted = TutorialHooks.beginRun(player, room);

	// invincible ⇒ never explodes.
	const explosionAt = invincible ? math.huge : rollExplosionTime(riskParams);

	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);

	// La fusée décolle dès le début du gameplay, à une vitesse pilotée par le stat
	// Rocket Speed du joueur (1 = rampe). Sa vélocité pilote ensuite le multiplicateur.
	// Un run scripté peut la ralentir (tutorial) ; hors tutorial le facteur vaut 1.
	// `launchClock` = horloge de référence du vol : `os.clock() - launchClock` donne le
	// temps de vol réel (précis à la frame), à comparer à la deadline d'explosion pour
	// mesurer le Perfect Claim. La boucle risque, elle, n'avance que par pas de TICK_RATE.
	const launchClock = os.clock();
	const effectiveSpeed = rocketSpeed * (scripted?.speedFactor ?? 1);
	RocketLauncher.launch(room, effectiveSpeed);

	// Cheat de dev : annonce l'issue déjà tirée du vol (voir CheatConfig). C'est l'état AU
	// DÉCOLLAGE — en tutorial, un run scripté peut réécrire sa deadline au claim.
	if (logExplosionForecast) logForecast(player, scripted?.explosionAt() ?? explosionAt, effectiveSpeed, baseCash);

	// Analytics: run started (custom counter + funnel step 1 + onboarding step 2).
	AnalyticsService.custom(player, "RocketLaunched", rocketSpeed);
	AnalyticsService.runStep(player, runId, 1, "Launch");
	AnalyticsService.onboardingStep(player, 2, "Launch");

	// Claim : le joueur VERROUILLE le multiplicateur courant en gain garanti. La fusée ne
	// s'arrête PAS — elle continue de monter (le multiplicateur affiché grimpe encore,
	// purement visuel) jusqu'à l'explosion, où le payout se fait au multiplicateur
	// verrouillé EXACT (voir la boucle risque plus bas). Remplace l'ancien "release".
	let claimed = false;
	let claimedMultiplier = STARTING_MULTIPLIER;
	const claimConn = Events.ClaimButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive || claimed) return;
		claimed = true;

		// Perfect Claim : le claim tombe dans la toute dernière fenêtre avant l'explosion
		// PRÉVUE → gain ×3. La deadline est lue AVANT scripted.onClaim(), qui la réécrit
		// en tutorial (sinon un run scripté offrirait un perfect gratuit).
		const deadline = scripted !== undefined ? scripted.explosionAt() : explosionAt;
		const remaining = deadline - (os.clock() - launchClock);
		const perfect = remaining <= perfectClaimWindow(deadline); // invincible ⇒ deadline ∞ ⇒ jamais perfect

		// Critical Claim : coup de dé pur à chaque claim (5 %) → ×10 sur le gain verrouillé.
		// Indépendant du Perfect Claim : les deux peuvent tomber ensemble et se multiplient.
		// Cheat de dev : `boostCriticalClaim` monte la chance à 50 % (voir CheatConfig).
		const criticalChance = boostCriticalClaim ? boostedCriticalClaimChance : CRITICAL_CLAIM_CHANCE;
		const critical = math.random() < criticalChance;

		// Valeur autoritative exacte au moment du claim, ×3 si Perfect Claim et ×10 si
		// Critical Claim. Toutes les branches de payout (explosion post-claim, Go Home) et
		// la popup de fin lisent ce multiplicateur tel quel — les bonus sont donc déjà
		// dedans partout.
		claimedMultiplier =
			currentMultiplier * (perfect ? PERFECT_CLAIM_MULTIPLIER : 1) * (critical ? CRITICAL_CLAIM_MULTIPLIER : 1);
		Events.ClaimAcceptedEvent.FireClient(player, claimedMultiplier, perfect, critical);
		scripted?.onClaim(); // tutorial : relance la fusée gelée + programme l'explosion

		// Analytics: claim locked (custom counter + funnel step 2 + onboarding step 3).
		AnalyticsService.custom(player, "RunClaimed", claimedMultiplier);
		if (perfect) AnalyticsService.custom(player, "PerfectClaim", claimedMultiplier);
		if (critical) AnalyticsService.custom(player, "CriticalClaim", claimedMultiplier);
		AnalyticsService.runStep(player, runId, 2, "Claim");
		AnalyticsService.onboardingStep(player, 3, "Claim");
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

		// Analytics: win banked early (Go Home) — funnel step 3 + custom counter.
		AnalyticsService.runStep(player, runId, 3, "Banked");
		AnalyticsService.custom(player, "RunGoHome", earned);

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
			// La deadline est relue à CHAQUE tour : le tutorial la réécrit au claim.
			const deadline = scripted !== undefined ? scripted.explosionAt() : explosionAt;
			// Avance jusqu'au prochain pas sans jamais dépasser l'instant d'explosion
			// précalculé → l'explosion tombe pile à l'heure.
			const nextStep = math.min(timeHeld + TICK_RATE, deadline);
			task.wait(nextStep - timeHeld);
			if (!isActive) break;

			timeHeld = nextStep;

			if (!invincible && timeHeld >= deadline) {
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

					// Analytics: guaranteed win landed after the explosion — funnel step 3.
					AnalyticsService.runStep(player, runId, 3, "Banked");
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

					// Analytics: run lost (never claimed) — custom counter with the multiplier
					// the player greeded to. No funnel step 3 → the drop-off is the loss rate.
					AnalyticsService.custom(player, "RunLost", currentMultiplier);
				}
				return;
			}
		}
	});
}
