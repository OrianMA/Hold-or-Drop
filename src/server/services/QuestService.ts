import { DataStoreService, Players, Workspace } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT, questCheatKey, questCheatTokens } from "server/modules/CheatConfig";
import { Events } from "shared/Event";
import { QUESTS, QUEST_RESET_SECONDS, Quest, QuestMetric, questProgressAttr, questResetAttr } from "shared/QuestConfig";
import { PlayerDataService } from "./PlayerDataService";
import { AnalyticsService } from "./AnalyticsService";

// Autorité des quêtes (§6.26). Tient la progression de chaque joueur, verse les
// ScrollToken à l'accomplissement et publie tout via des ATTRIBUTS joueur — donc
// répliqués vers le client sans le moindre RemoteEvent :
//   Q_<id>  progression courante
//   QR_<id> instant de reset en temps SERVEUR (0 = quête disponible)
//
// Le client ne fait jamais que lire ces attributs. Les seuls points d'entrée de
// progression sont les appels à `report` posés dans le code de jeu :
// ButtonInGameModule (décollage + claim) et ShopService (achat validé).
//
// Persistance : store dédié (même patron que PlayerProgressionService), avec le
// cooldown stocké en os.time() ABSOLU pour qu'il continue de s'écouler hors ligne.
// L'attribut, lui, est exprimé en Workspace:GetServerTimeNow() : c'est la seule
// horloge que client et serveur partagent réellement.

const STORE_NAME = "QuestData_v1";
const dataStore = DataStoreService.GetDataStore(STORE_NAME);

// Cadence du balayage des cooldowns arrivés à terme. 1s : le libellé côté client
// descend à la seconde, inutile d'être plus fin.
const COOLDOWN_TICK = 1;

interface QuestState {
	// questId → progression (peut être fractionnaire pour MultiplierTotal).
	progress: Map<string, number>;
	// questId → os.time() de fin de cooldown. Absent = quête disponible.
	resetAt: Map<string, number>;
}

// Forme persistée (tables plates, indexées par questId).
interface StoredQuestData {
	progress: { [questId: string]: number };
	resetAt: { [questId: string]: number };
}

const states = new Map<Player, QuestState>();
// Seuls les joueurs dont le chargement a RÉUSSI sont sauvegardables — un échec
// transitoire du DataStore ne doit jamais écraser une progression existante.
const loadedPlayers = new Set<Player>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function emptyState(): QuestState {
	return { progress: new Map<string, number>(), resetAt: new Map<string, number>() };
}

// Écrit le couple d'attributs d'une quête. `resetAt` est converti d'os.time()
// (persistant) vers le temps serveur (partagé avec le client) au moment de la
// publication : les deux horloges avancent à la même vitesse, seul l'offset diffère.
function publish(player: Player, state: QuestState, quest: Quest): void {
	player.SetAttribute(questProgressAttr(quest.id), state.progress.get(quest.id) ?? 0);

	const deadline = state.resetAt.get(quest.id);
	if (deadline === undefined) {
		player.SetAttribute(questResetAttr(quest.id), 0);
		return;
	}
	const remaining = math.max(0, deadline - os.time());
	player.SetAttribute(questResetAttr(quest.id), Workspace.GetServerTimeNow() + remaining);
}

function publishAll(player: Player, state: QuestState): void {
	for (const quest of QUESTS) publish(player, state, quest);
}

function loadState(player: Player): QuestState | undefined {
	if (RESET_DATA_CHEAT) {
		warn(`QuestService: resetData cheat — wiping in-memory state for ${player.Name}`);
		return emptyState();
	}

	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`QuestService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	const state = emptyState();
	if (result === undefined || !typeIs(result, "table")) return state;

	const stored = result as Partial<StoredQuestData>;
	for (const quest of QUESTS) {
		const deadline = stored.resetAt?.[quest.id];
		// Un cooldown expiré pendant la déconnexion est simplement oublié — et avec
		// lui la progression, exactement comme un reset survenu en ligne.
		if (typeIs(deadline, "number") && deadline > os.time()) {
			state.resetAt.set(quest.id, deadline);
			state.progress.set(quest.id, quest.target);
			continue;
		}
		if (typeIs(deadline, "number")) continue;

		const progress = stored.progress?.[quest.id];
		if (typeIs(progress, "number")) state.progress.set(quest.id, math.max(0, progress));
	}
	return state;
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;
	const state = states.get(player);
	if (!state) return;

	const data: StoredQuestData = { progress: {}, resetAt: {} };
	for (const [questId, value] of state.progress) data.progress[questId] = value;
	for (const [questId, value] of state.resetAt) data.resetAt[questId] = value;

	const [success, err] = pcall(() => dataStore.SetAsync(keyFor(player), data));
	if (!success) warn(`QuestService: failed to save ${player.Name}: ${err}`);
}

function setupPlayer(player: Player): void {
	const loaded = loadState(player);
	const state = loaded ?? emptyState();
	states.set(player, state);
	if (loaded !== undefined) loadedPlayers.add(player);
	publishAll(player, state);
}

// Quête accomplie : la progression est figée à l'objectif (la barre reste pleine
// pendant le cooldown), la récompense est versée, le cooldown démarre.
function complete(player: Player, state: QuestState, quest: Quest): void {
	state.progress.set(quest.id, quest.target);
	state.resetAt.set(quest.id, os.time() + QUEST_RESET_SECONDS);
	publish(player, state, quest);

	PlayerDataService.add(player, "ScrollTokens", quest.reward);

	// Présentation : le client s'occupe du bandeau Epic + de la pluie d'icônes.
	Events.QuestCompletedEvent.FireClient(player);
	// Analytics : une quête accomplie = un événement. Le compte du dashboard donne le
	// NOMBRE de quêtes accomplies, les champs le découpage par DIFFICULTÉ et par
	// métrique (l'id vaut difficulté_métrique, donc il n'est pas renvoyé en plus).
	// La valeur est la récompense versée → somme = tokens émis par les quêtes.
	AnalyticsService.custom(player, "QuestCompleted", quest.reward, quest.difficulty, quest.metric);
}

// Fin de cooldown : la quête repart de zéro et redevient "Enable".
function rearm(player: Player, state: QuestState, quest: Quest): void {
	state.resetAt.delete(quest.id);
	state.progress.delete(quest.id);
	publish(player, state, quest);
}

function tickCooldowns(): void {
	const now = os.time();
	for (const [player, state] of states) {
		if (state.resetAt.isEmpty()) continue;
		for (const quest of QUESTS) {
			const deadline = state.resetAt.get(quest.id);
			if (deadline !== undefined && deadline <= now) rearm(player, state, quest);
		}
	}
}

export const QuestService = {
	init(): void {
		Players.PlayerAdded.Connect(setupPlayer);
		for (const player of Players.GetPlayers()) setupPlayer(player);

		Players.PlayerRemoving.Connect((player) => {
			savePlayer(player);
			loadedPlayers.delete(player);
			states.delete(player);
		});

		// Roblox waits up to 30s on BindToClose — save everyone in parallel so a
		// slow save doesn't starve the others before the deadline.
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

		task.spawn(() => {
			while (true) {
				task.wait(COOLDOWN_TICK);
				tickCooldowns();
			}
		});

		// Cheat de dev (touche U) : termine la première quête disponible par le chemin
		// NORMAL — récompense, bandeau Epic et pluie d'icônes compris — puis crédite le
		// bonus de test. L'event n'est même pas branché quand le cheat est éteint, il
		// est donc totalement inerte en production.
		if (questCheatKey) {
			Events.QuestCheatEvent.OnServerEvent.Connect((player) => {
				const state = states.get(player);
				if (!state) return;

				const available = QUESTS.find((quest) => state.resetAt.get(quest.id) === undefined);
				// Tout en cooldown : on garde au moins la célébration.
				if (available) complete(player, state, available);
				else Events.QuestCompletedEvent.FireClient(player);

				PlayerDataService.add(player, "ScrollTokens", questCheatTokens);
			});
		}
	},

	// SEUL point d'entrée de progression. Alimente toutes les quêtes de la métrique
	// (une par difficulté) ; celles en cooldown sont ignorées.
	report(player: Player, metric: QuestMetric, amount: number): void {
		if (amount <= 0) return;
		const state = states.get(player);
		if (!state) return;

		for (const quest of QUESTS) {
			if (quest.metric !== metric) continue;
			if (state.resetAt.get(quest.id) !== undefined) continue; // en cooldown

			const nextProgress = (state.progress.get(quest.id) ?? 0) + amount;
			if (nextProgress >= quest.target) {
				complete(player, state, quest);
			} else {
				state.progress.set(quest.id, nextProgress);
				publish(player, state, quest);
			}
		}
	},
};
