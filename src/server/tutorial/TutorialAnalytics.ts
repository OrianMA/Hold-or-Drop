import { AnalyticsService } from "server/services/AnalyticsService";
import { TUTORIAL_STEPS } from "shared/tutorial/TutorialSteps";

// Toute la sémantique analytics du tutorial (le jeu de base ne gagne qu'un helper
// générique, AnalyticsService.funnelStep). Voir le spec tutorial §9.
//
//   Funnel "Tutorial" : un pas à l'ENTRÉE de chaque step → le drop-off entre N et N+1
//   est le taux d'abandon PENDANT le step N. funnelSessionId = le runId persisté, donc
//   un joueur qui revient après un relog reste dans le même funnel.

const FUNNEL = "Tutorial";

// "Step03" — index 0-based → libellé 1-based zéro-paddé, pour que le dashboard trie
// les marches dans l'ordre du tutorial et pas dans l'ordre alphabétique.
function stepLabel(index: number): string {
	return string.format("Step%02d", index + 1);
}

export const TutorialAnalytics = {
	// Dénominateur : combien de joueurs commencent (ou reprennent) le tutorial.
	started(player: Player, resumed: boolean): void {
		AnalyticsService.custom(player, "TutorialStarted", 1, resumed ? "Resumed" : "Fresh");
	},

	// Entrée dans un step (index 0-based → pas de funnel 1-based).
	stepEntered(player: Player, runId: string, index: number, stepId: string): void {
		AnalyticsService.funnelStep(player, FUNNEL, runId, index + 1, stepId);
	},

	// Sortie d'un step, avec le temps passé dessus : repère les steps qui bloquent.
	// COMBIEN DE STEPS ACCOMPLIS : le compte de cet événement est le nombre total de
	// steps terminés, et le champ `StepNN` (1-based, donc trié comme à l'écran) le
	// découpe par marche — le décrochage se lit d'un coup d'œil.
	stepDone(player: Player, stepId: string, seconds: number, index: number): void {
		AnalyticsService.custom(player, "TutorialStepDone", seconds, stepId, stepLabel(index));
	},

	// Tutorial terminé SANS skip : dernière marche du funnel + durée totale.
	// Un joueur ne peut finir qu'une fois → le compte de TutorialCompleted est le
	// NOMBRE DE JOUEURS qui ont fini, et TutorialStarted en est le dénominateur.
	completed(player: Player, runId: string, totalSeconds: number): void {
		AnalyticsService.funnelStep(player, FUNNEL, runId, TUTORIAL_STEPS.size() + 1, "Done");
		AnalyticsService.custom(player, "TutorialCompleted", totalSeconds, "NoSkip", `${TUTORIAL_STEPS.size()}Steps`);
	},

	// Skip : la valeur est le temps écoulé, le breakdown le step d'où il est sorti et
	// le NOMBRE DE STEPS déjà accomplis avant d'abandonner. Un joueur ne peut skipper
	// qu'une fois → le compte de l'événement = le nombre de joueurs qui ont skip.
	skipped(player: Player, stepId: string, seconds: number, stepsDone: number): void {
		AnalyticsService.custom(player, "TutorialSkipped", seconds, stepId, `${stepsDone}Steps`);
	},
};
