import { Players } from "@rbxts/services";
import { Room } from "server/rooms/Room";
import { RocketLauncher } from "server/modules/RocketLauncher";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { ScriptedRun } from "shared/tutorial/TutorialTypes";
import { TutorialService } from "./TutorialService";

// Met en scène le run truqué du tutorial. Le jeu de base ne connaît que le handle
// ci-dessous : il lui demande la deadline d'explosion à chaque tick et le prévient du
// claim. Tout le scénario (quand geler, quand relancer, quel délai) vit ici.
//
// La deadline est RÉÉCRITE au claim (explodeAfterClaim) : c'est pourquoi le jeu doit la
// relire à chaque tour de boucle plutôt que de la lire une fois au décollage.

// Si le tutorial est coupé (skip) pendant un run truqué sans risque, la fusée volerait
// pour toujours. On résout alors le run en le faisant exploser peu après.
const ABORT_EXPLODE_DELAY = 2;

export interface ScriptedRunHandle {
	// Secondes de vol au bout desquelles la fusée doit exploser (math.huge = jamais).
	// Syntaxe "propriété-fonction" (pas de raccourci méthode) : l'objet retourné assigne
	// des flèches via ":" — roblox-ts exigerait sinon un appel self (":") au lieu de ".".
	explosionAt: () => number;
	// Le joueur vient de claim.
	onClaim: () => void;
	// Multiplie la vitesse de décollage (1 = vitesse normale du joueur). Lu UNE fois, juste
	// avant launch() — contrairement à la deadline, il n'a plus de sens une fois en vol.
	speedFactor: number;
}

const activeHandles = new Map<Player, { abort: () => void }>();

// Identité du run courant par joueur (compteur incrémenté à chaque begin()). Sans ça, un
// timer de gel programmé par un run précédent — écrasé dans activeHandles par un nouveau
// begin() sans abort() intermédiaire — ne serait retenu que par stillRunning(), qui ne
// vérifie que la room, pas l'identité du run. Le timer périmé pourrait alors geler le
// NOUVEAU run avec la config de l'ANCIEN, sans que le flag `frozen` du nouveau run ne
// bouge : la fusée resterait gelée pour toujours.
const runGenerations = new Map<Player, number>();

export const TutorialRunDirector = {
	begin(player: Player, room: Room, run: ScriptedRun): ScriptedRunHandle {
		const generation = (runGenerations.get(player) ?? 0) + 1;
		runGenerations.set(player, generation);
		// Ce run n'est plus le run courant du joueur si begin() a été rappelé entre-temps.
		const isCurrentRun = (): boolean => runGenerations.get(player) === generation;

		const startedAt = os.clock();
		// noRisk (ou rien de précisé) → aucune explosion tant que le script n'en programme
		// pas une. explodeAt fixe l'instant depuis le décollage.
		let deadline = run.explodeAt ?? math.huge;
		let frozen = false;

		const elapsed = (): number => os.clock() - startedAt;
		// Le run n'est plus le nôtre si la session a été nettoyée ou a changé de room.
		const stillRunning = (): boolean => ButtonSessionService.getSession(player)?.room === room;

		if (run.freezeAt !== undefined) {
			task.delay(run.freezeAt, () => {
				// Deux gardes distinctes : isCurrentRun (« c'est toujours MON run ? ») et
				// stillRunning (« un run quelconque tourne-t-il encore pour ce joueur ? »).
				if (!isCurrentRun()) return;
				if (!stillRunning()) return;
				RocketLauncher.freeze(room);
				frozen = true;
				// Saut d'étape DÉTERMINISTE : on ne dépend pas du timing d'un signal client.
				if (run.advanceToOnFreeze !== undefined) {
					TutorialService.advanceTo(player, run.advanceToOnFreeze);
				}
			});
		}

		activeHandles.set(player, {
			abort: () => {
				if (frozen) {
					RocketLauncher.unfreeze(room);
					frozen = false;
				}
				// Le run doit se terminer tout seul, sinon la fusée reste en l'air.
				if (deadline === math.huge) deadline = elapsed() + ABORT_EXPLODE_DELAY;
			},
		});

		return {
			explosionAt: () => deadline,
			speedFactor: run.speedFactor ?? 1,
			onClaim: () => {
				if (run.unfreezeOnClaim === true && frozen) {
					RocketLauncher.unfreeze(room);
					frozen = false;
				}
				if (run.explodeAfterClaim !== undefined) {
					deadline = elapsed() + run.explodeAfterClaim;
				}
			},
		};
	},

	// Appelé quand le tutorial se termine (skip) : un run scripté en cours doit pouvoir
	// se conclure normalement.
	abort(player: Player): void {
		activeHandles.get(player)?.abort();
		activeHandles.delete(player);
	},
};

// Le service annonce la fin du tutorial ; le director résout le run en vol. Enregistré à
// la première charge du module (ButtonInGameModule → TutorialHooks → ici).
TutorialService.setRunAbortHandler((player) => TutorialRunDirector.abort(player));

// Un joueur qui se déconnecte en plein run truqué ne passe jamais par abort() : sans ce
// nettoyage, activeHandles et runGenerations grossiraient indéfiniment sur la durée de
// vie du serveur. Enregistré ici en effet de bord au chargement du module, comme
// setRunAbortHandler ci-dessus (ce module n'a pas d'init()).
Players.PlayerRemoving.Connect((player) => {
	activeHandles.delete(player);
	runGenerations.delete(player);
});
