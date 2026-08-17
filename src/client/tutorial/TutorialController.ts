import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { TutorialStep } from "shared/tutorial/TutorialTypes";
import { stepById } from "shared/tutorial/TutorialSteps";
import { TutorialUI } from "./TutorialUI";
import { TutorialSkipButton } from "./TutorialSkipButton";

// Orchestre le rendu du tutorial côté client. Le serveur publie l'étape courante dans
// l'attribut répliqué TutorialStep ("" = terminé) ; ce contrôleur la lit, monte la mise
// en scène du step, et remonte la complétion via TutorialAdvanceEvent.

const STEP_ATTR = "TutorialStep";
const SKIP_ID = "skip";

const player = Players.LocalPlayer;

// Démontage de la mise en scène du step courant.
let teardown: (() => void) | undefined;

function clearStep(): void {
	if (teardown) {
		teardown();
		teardown = undefined;
	}
	TutorialUI.hideBanner();
}

function showStep(step: TutorialStep): void {
	clearStep();
	TutorialUI.ensure();
	TutorialUI.setText(step.text);
}

function render(): void {
	const stepId = (player.GetAttribute(STEP_ATTR) as string | undefined) ?? "";
	if (stepId === "") {
		// Tutorial terminé : on démonte tout, plus une seule connexion active.
		clearStep();
		TutorialSkipButton.setVisible(false);
		TutorialUI.destroy();
		return;
	}

	const step = stepById(stepId);
	if (!step) {
		warn(`TutorialController: step inconnu "${stepId}"`);
		return;
	}
	TutorialSkipButton.setVisible(true);
	showStep(step);
}

export function init(): void {
	TutorialSkipButton.init(() => Events.TutorialAdvanceEvent.FireServer(SKIP_ID));
	// Masqué par défaut : un joueur qui a déjà fini ne doit jamais le voir.
	TutorialSkipButton.setVisible(false);

	player.GetAttributeChangedSignal(STEP_ATTR).Connect(render);
	// L'attribut peut déjà être arrivé avant l'init du client.
	render();
}
