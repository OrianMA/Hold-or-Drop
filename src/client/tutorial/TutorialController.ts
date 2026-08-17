import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { TutorialStep } from "shared/tutorial/TutorialTypes";
import { stepById } from "shared/tutorial/TutorialSteps";
import { TutorialUI } from "./TutorialUI";
import { TutorialSkipButton } from "./TutorialSkipButton";
import { TutorialTriggers } from "./TutorialTriggers";
import { TutorialArrow } from "./TutorialArrow";
import { TutorialTargets } from "./TutorialTargets";
import { TutorialFocus } from "./TutorialFocus";
import { TutorialGate } from "./TutorialGate";
import { setTutorialActive } from "client/behaviors/RocketLaunchBehavior";

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
	TutorialArrow.clear();
	TutorialFocus.clear();
	TutorialGate.unlock();
	TutorialUI.hideBanner();
}

function showStep(step: TutorialStep): void {
	clearStep();
	TutorialUI.ensure();
	TutorialUI.setText(step.text);

	// Pointage. Le monde peut yielder (streaming) → task.spawn, et on vérifie que le
	// step n'a pas changé entre-temps avant d'afficher quoi que ce soit.
	const target = step.target;
	if (target.kind === "gui") {
		const gui = TutorialTargets.resolveGui(target.path);
		if (gui) {
			TutorialArrow.pointAtGui(gui);
			if (step.focus !== undefined) {
				TutorialFocus.apply(gui, step.focus);
				TutorialGate.lockGui(gui);
			}
		} else warn(`TutorialController: cible GUI introuvable "${target.path}"`);
	} else if (target.kind === "world") {
		const shownFor = step.id;
		task.spawn(() => {
			const part = TutorialTargets.resolveWorld(target.part);
			const currentId = (player.GetAttribute(STEP_ATTR) as string | undefined) ?? "";
			if (!part || currentId !== shownFor) return;
			TutorialArrow.pointAtWorld(part);
			TutorialGate.lockPrompts(part); // seul le prompt de la cible reste actif
		});
	} else {
		// Steps sans cible (watch-launch, claim-explode) : rien à pointer, mais tout doit
		// rester verrouillé. C'est ce qui bloque "Go Home" pendant le step post-claim —
		// un clic chanceux dans la fenêtre de re-arm sauterait l'explosion que le tutorial
		// veut montrer — et empêche un claim prématuré avant le gel.
		// Le bouton Skip est explicitement épargné par lockGui.
		TutorialGate.lockGui(undefined);
	}

	// La complétion est remontée au serveur, qui valide que c'est bien le step courant.
	const stopWatching = TutorialTriggers.watch(step, () => {
		Events.TutorialAdvanceEvent.FireServer(step.id);
	});
	teardown = () => stopWatching();
}

function render(): void {
	const stepId = (player.GetAttribute(STEP_ATTR) as string | undefined) ?? "";
	if (stepId === "") {
		// Tutorial terminé : on démonte tout, plus une seule connexion active.
		clearStep();
		setTutorialActive(false);
		TutorialSkipButton.setVisible(false);
		TutorialUI.destroy();
		return;
	}

	const step = stepById(stepId);
	if (!step) {
		// Id inconnu : on ne sait pas quoi afficher, mais le tutorial est toujours en cours
		// côté serveur (attribut non vide). On démonte juste la présentation du step
		// précédent — même teardown que pour l'attribut vide, moins TutorialUI.destroy() —
		// pour ne pas laisser le texte/highlight d'un ancien step à l'écran.
		warn(`TutorialController: step inconnu "${stepId}"`);
		clearStep();
		TutorialSkipButton.setVisible(false);
		return;
	}
	setTutorialActive(true);
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
