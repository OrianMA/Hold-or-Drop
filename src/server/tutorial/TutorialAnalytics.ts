import { AnalyticsService } from "server/services/AnalyticsService";
import { TUTORIAL_STEPS } from "shared/tutorial/TutorialSteps";

// Toute la sémantique analytics du tutorial (le jeu de base ne gagne qu'un helper
// générique, AnalyticsService.funnelStep). Voir le spec tutorial §9.
//
//   Funnel "Tutorial" : un pas à l'ENTRÉE de chaque step → le drop-off entre N et N+1
//   est le taux d'abandon PENDANT le step N. funnelSessionId = le runId persisté, donc
//   un joueur qui revient après un relog reste dans le même funnel.

const FUNNEL = "Tutorial";

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
	stepDone(player: Player, stepId: string, seconds: number): void {
		AnalyticsService.custom(player, "TutorialStepDone", seconds, stepId);
	},

	// Tutorial terminé SANS skip : dernière marche du funnel + durée totale.
	completed(player: Player, runId: string, totalSeconds: number): void {
		AnalyticsService.funnelStep(player, FUNNEL, runId, TUTORIAL_STEPS.size() + 1, "Done");
		AnalyticsService.custom(player, "TutorialCompleted", totalSeconds, "NoSkip");
	},

	// Skip : la valeur est le temps écoulé, le breakdown le step d'où il est sorti.
	skipped(player: Player, stepId: string, seconds: number): void {
		AnalyticsService.custom(player, "TutorialSkipped", seconds, stepId);
	},
};
