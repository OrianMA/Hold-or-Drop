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
}

const activeHandles = new Map<Player, { abort: () => void }>();

export const TutorialRunDirector = {
	begin(player: Player, room: Room, run: ScriptedRun): ScriptedRunHandle {
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
