import { DataStoreService, HttpService, Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { TutorialStep } from "shared/tutorial/TutorialTypes";
import { TUTORIAL_STEPS, firstStepId, stepById, stepIndexById } from "shared/tutorial/TutorialSteps";
import { forceTutorial } from "server/modules/CheatConfig";
import { TutorialAnalytics } from "./TutorialAnalytics";

// État du tutorial par joueur. Le SERVEUR est la source de vérité de l'étape courante :
// il la publie via l'attribut répliqué `TutorialStep` (le client ne fait que lire et
// rendre), la persiste dans son propre store et l'avance sur signal client.
//
// Store dédié PlayerTutorial_v1 : aucune migration ni risque sur PlayerData/Progression,
// et retirer le tutorial ne laisse qu'un store orphelin inoffensif.

const STEP_ATTR = "TutorialStep";
const STORE_NAME = "PlayerTutorial_v1";
const SKIP_ID = "skip";

interface TutorialSave {
	step: string; // id du step courant ("" une fois terminé)
	done: boolean; // terminé (complété OU skippé) → module inerte à vie
	runId: string; // GUID de la tentative — garde le même funnel analytics après un relog
	elapsed: number; // secondes cumulées passées dans le tuto (hors temps hors-ligne)
}

interface TutorialState extends TutorialSave {
	stepEnteredAt: number; // os.time() de l'entrée dans le step courant
}

const dataStore = DataStoreService.GetDataStore(STORE_NAME);
const states = new Map<Player, TutorialState>();
// Seuls les joueurs dont le load a réussi sont sauvegardables — un échec transitoire
// ne doit jamais écraser une progression existante.
const loadedPlayers = new Set<Player>();

// Appelé quand le tutorial se termine, pour qu'un run truqué encore en vol puisse se
// conclure (sinon une fusée sans risque volerait indéfiniment). Enregistré par
// TutorialRunDirector — un callback plutôt qu'un import, pour éviter un cycle de require.
let runAbortHandler: ((player: Player) => void) | undefined;

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function newRunId(): string {
	const [ok, id] = pcall(() => HttpService.GenerateGUID(false));
	return ok ? (id as string) : `${tick()}`;
}

function freshSave(): TutorialSave {
	return { step: firstStepId(), done: false, runId: newRunId(), elapsed: 0 };
}

function loadSave(player: Player): TutorialSave | undefined {
	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`TutorialService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined || !typeIs(result, "table")) return freshSave();

	const loaded = result as Partial<TutorialSave>;
	const save = freshSave();
	if (typeIs(loaded.step, "string")) save.step = loaded.step;
	if (loaded.done === true) save.done = true;
	if (typeIs(loaded.runId, "string")) save.runId = loaded.runId;
	if (typeIs(loaded.elapsed, "number")) save.elapsed = math.max(0, loaded.elapsed);
	// Un id inconnu (step renommé/retiré) fait repartir au début plutôt que de bloquer.
	if (!save.done && stepIndexById(save.step) === undefined) save.step = firstStepId();
	return save;
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;
	const state = states.get(player);
	if (!state) return;

	const data: TutorialSave = {
		step: state.step,
		done: state.done,
		runId: state.runId,
		elapsed: state.elapsed,
	};
	const [success, err] = pcall(() => dataStore.SetAsync(keyFor(player), data));
	if (!success) warn(`TutorialService: failed to save ${player.Name}: ${err}`);
}

// Publie l'étape courante vers le client (attribut répliqué). "" = plus de tutorial.
function publish(player: Player, stepId: string): void {
	player.SetAttribute(STEP_ATTR, stepId);
}

// Referme le step courant : cumule son temps et renvoie sa durée en secondes.
function closeStep(state: TutorialState): number {
	const spent = math.max(0, os.time() - state.stepEnteredAt);
	state.elapsed += spent;
	state.stepEnteredAt = os.time();
	return spent;
}

function enterStep(player: Player, state: TutorialState, stepId: string): void {
	state.step = stepId;
	state.stepEnteredAt = os.time();
	publish(player, stepId);
	const index = stepIndexById(stepId);
	if (index !== undefined) TutorialAnalytics.stepEntered(player, state.runId, index, stepId);
}

// `skipped` distingue les deux fins : un tutorial complété ne logge JAMAIS
// TutorialSkipped, et inversement.
function finishTutorial(player: Player, state: TutorialState, skipped: boolean): void {
	const lastStep = state.step;
	const spent = closeStep(state);
	// L'index 0-based du step quitté EST le nombre de steps déjà accomplis avant lui.
	if (skipped) TutorialAnalytics.skipped(player, lastStep, state.elapsed, stepIndexById(lastStep) ?? 0);
	else {
		// La durée du step (stepDone) a déjà été comptabilisée par l'appelant (advanceOne).
		// Ne pas la re-logger ici pour éviter un doublon.
		TutorialAnalytics.completed(player, state.runId, state.elapsed);
	}
	state.done = true;
	state.step = "";
	publish(player, "");
	if (runAbortHandler !== undefined) runAbortHandler(player);
	savePlayer(player);
}

// Avance d'exactement un step (ou termine si c'était le dernier).
function advanceOne(player: Player, state: TutorialState): void {
	const index = stepIndexById(state.step);
	if (index === undefined) {
		finishTutorial(player, state, false);
		return;
	}
	const leaving = state.step;
	const spent = closeStep(state);
	TutorialAnalytics.stepDone(player, leaving, spent, index);

	const nextIndex = index + 1;
	if (nextIndex >= TUTORIAL_STEPS.size()) {
		finishTutorial(player, state, false);
		return;
	}
	enterStep(player, state, TUTORIAL_STEPS[nextIndex].id);
	savePlayer(player);
}

function setupPlayer(player: Player): void {
	const save = loadSave(player);
	if (save !== undefined) loadedPlayers.add(player);

	const resolved = save ?? freshSave();
	// forceTutorial ignore la sauvegarde : on repart du premier step.
	if (forceTutorial) {
		resolved.done = false;
		resolved.step = firstStepId();
		resolved.elapsed = 0;
		resolved.runId = newRunId();
	}

	if (resolved.done) {
		states.set(player, { ...resolved, step: "", stepEnteredAt: os.time() });
		publish(player, "");
		return;
	}

	const state: TutorialState = { ...resolved, stepEnteredAt: os.time() };
	states.set(player, state);
	publish(player, state.step);

	// "Resumed" = le joueur reprend un tutorial commencé dans une session précédente.
	const resumed = state.step !== firstStepId() || state.elapsed > 0;
	TutorialAnalytics.started(player, resumed);
	const index = stepIndexById(state.step);
	if (index !== undefined) TutorialAnalytics.stepEntered(player, state.runId, index, state.step);
}

export const TutorialService = {
	init(): void {
		Players.PlayerAdded.Connect((player) => task.spawn(() => setupPlayer(player)));
		for (const player of Players.GetPlayers()) task.spawn(() => setupPlayer(player));

		Events.TutorialAdvanceEvent.OnServerEvent.Connect((player, stepId) => {
			if (!typeIs(stepId, "string")) return;
			const state = states.get(player);
			if (!state || state.done) return;

			if (stepId === SKIP_ID) {
				TutorialService.finish(player, true);
				return;
			}
			TutorialService.advance(player, stepId);
		});

		Players.PlayerRemoving.Connect((player) => {
			const state = states.get(player);
			if (state && !state.done) closeStep(state);
			savePlayer(player);
			states.delete(player);
			loadedPlayers.delete(player);
		});

		game.BindToClose(() => {
			const players = Players.GetPlayers();
			if (players.size() === 0) return;
			let remaining = players.size();
			for (const player of players) {
				task.spawn(() => {
					savePlayer(player);
					remaining -= 1;
				});
			}
			while (remaining > 0) task.wait(0.1);
		});
	},

	isActive(player: Player): boolean {
		const state = states.get(player);
		return state !== undefined && !state.done;
	},

	getCurrentStep(player: Player): TutorialStep | undefined {
		const state = states.get(player);
		if (!state || state.done) return undefined;
		return stepById(state.step);
	},

	// Avance SEULEMENT si `stepId` est bien le step courant — un event client en retard
	// ou rejoué ne peut donc pas sauter une étape.
	advance(player: Player, stepId: string): void {
		const state = states.get(player);
		if (!state || state.done || state.step !== stepId) return;
		advanceOne(player, state);
	},

	// Avance jusqu'à `stepId` en traversant les steps intermédiaires un par un (chaque
	// step est donc bien entré/sorti, ce qui garde le funnel analytique complet).
	// Utilisé par la mise en scène du run truqué : le saut est déterministe, il ne dépend
	// pas du timing d'un signal client.
	advanceTo(player: Player, stepId: string): void {
		const state = states.get(player);
		if (!state || state.done) return;
		const target = stepIndexById(stepId);
		if (target === undefined) return;

		let guard = 0;
		while (!state.done && stepIndexById(state.step) !== undefined) {
			const current = stepIndexById(state.step) as number;
			if (current >= target) break;
			advanceOne(player, state);
			guard += 1;
			if (guard > TUTORIAL_STEPS.size()) break; // garde-fou anti-boucle
		}
	},

	finish(player: Player, skipped: boolean): void {
		const state = states.get(player);
		if (!state || state.done) return;
		finishTutorial(player, state, skipped);
	},

	// Enregistre le handler d'annulation de run truqué (voir runAbortHandler).
	setRunAbortHandler(handler: (player: Player) => void): void {
		runAbortHandler = handler;
	},

	// ── Dev (barre de commande / execute_luau) ────────────────────────────────
	devRestart(player: Player): void {
		const state: TutorialState = { ...freshSave(), stepEnteredAt: os.time() };
		states.set(player, state);
		loadedPlayers.add(player);
		enterStep(player, state, state.step);
		savePlayer(player);
	},

	devGoto(player: Player, stepId: string): void {
		if (stepIndexById(stepId) === undefined) {
			warn(`TutorialService.devGoto: step inconnu "${stepId}"`);
			return;
		}
		const state = states.get(player) ?? { ...freshSave(), stepEnteredAt: os.time() };
		state.done = false;
		states.set(player, state);
		loadedPlayers.add(player);
		enterStep(player, state, stepId);
		savePlayer(player);
	},
};
