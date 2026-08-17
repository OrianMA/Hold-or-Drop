import { Workspace } from "@rbxts/services";
import { TutorialUI } from "./TutorialUI";

// Verrouillage des interactions hors-scope pendant un step. 100 % client : c'est de
// l'UX, pas de la sécurité (le tutorial ne donne rien de plus que le jeu normal, et le
// serveur valide de toute façon chaque action).
//
// Division des responsabilités avec TutorialFocus : le dim MONTRE (assombrit, purement
// visuel, Active = false), TutorialGate BLOQUE (Interactable = false sur tout GuiButton
// hors cible/Skip). C'est l'UNIQUE mécanisme de blocage — ne pas réintroduire de frame
// "Active = true" dans TutorialFocus pour ça, ça repasserait au-dessus du bouton Skip
// (TutorialUI est à DisplayOrder 100, au-dessus de InGameUI) et le rendrait injoignable.
//
// L'état d'origine de chaque instance touchée est mémorisé et restauré — jamais de
// valeur "par défaut" réécrite à l'aveugle.

const lockedButtons = new Map<GuiButton, boolean>();
const lockedPrompts = new Map<ProximityPrompt, boolean>();

export const TutorialGate = {
	// Rend non-interactifs tous les GuiButton de InGameUI SAUF la cible et ses
	// descendants/ancêtres (le dim absorbe déjà la souris ; ceci couvre clavier/manette).
	lockGui(target: GuiObject | undefined): void {
		const root = TutorialUI.getInGameUI();
		if (!root) return;

		for (const descendant of root.GetDescendants()) {
			if (!descendant.IsA("GuiButton")) continue;
			const isTarget =
				target !== undefined && (descendant === target || descendant.IsDescendantOf(target));
			// Le bouton Skip doit rester cliquable en permanence.
			const isSkip = descendant.FindFirstAncestor("TutorialSkip") !== undefined;
			if (isTarget || isSkip) continue;

			if (!lockedButtons.has(descendant)) lockedButtons.set(descendant, descendant.Interactable);
			descendant.Interactable = false;
		}
	},

	// Désactive tous les ProximityPrompt sauf celui de `except` : le joueur ne peut pas
	// entrer dans la boutique avant l'heure. RoomPromptController reprend la main quand
	// on restaure.
	lockPrompts(except: BasePart | undefined): void {
		for (const descendant of Workspace.GetDescendants()) {
			if (!descendant.IsA("ProximityPrompt")) continue;
			if (except !== undefined && descendant.Parent === except) continue;
			if (!descendant.Enabled) continue;
			if (!lockedPrompts.has(descendant)) lockedPrompts.set(descendant, descendant.Enabled);
			descendant.Enabled = false;
		}
	},

	unlock(): void {
		for (const [button, interactable] of lockedButtons) {
			if (button.Parent !== undefined) button.Interactable = interactable;
		}
		lockedButtons.clear();

		for (const [prompt, enabled] of lockedPrompts) {
			if (prompt.Parent !== undefined) prompt.Enabled = enabled;
		}
		lockedPrompts.clear();
	},
};
