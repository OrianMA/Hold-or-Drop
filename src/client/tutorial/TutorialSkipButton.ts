import { Players } from "@rbxts/services";

// Le bouton Skip est AUTHORÉ DANS STUDIO (visuel maison) — le code ne fait que
// l'allumer/l'éteindre et écouter son clic. Hiérarchie attendue :
//   InGameUI/TutorialSkip (Frame)  ← visibilité pilotée ici
//     └── TutorialSkipFrame/TextButton
// Résolu par NOM en recherche récursive, pour que le frame puisse être déplacé dans
// Studio sans toucher au code. TutorialSkip est un frère du HUD (et non un enfant) :
// il survit donc au masquage du HUD pendant un run.

const ROOT_NAME = "TutorialSkip";
const BUTTON_NAME = "TextButton";

let root: Frame | undefined;
let connected = false;
// setVisible() appelle findRoot() à chaque step : si le frame Studio est absent, on ne
// veut avertir qu'une fois, pas spammer l'output à chaque changement d'étape.
let warnedMissing = false;

function findRoot(): Frame | undefined {
	if (root && root.Parent !== undefined) return root;
	const gui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const found = gui.FindFirstChild(ROOT_NAME, true);
	root = found?.IsA("Frame") ? found : undefined;
	if (!root && !warnedMissing) {
		warn(`TutorialSkipButton: ${ROOT_NAME} introuvable sous PlayerGui`);
		warnedMissing = true;
	}
	return root;
}

export const TutorialSkipButton = {
	init(onSkip: () => void): void {
		const frame = findRoot();
		if (!frame || connected) return;

		const button = frame.FindFirstChild(BUTTON_NAME, true);
		if (!button?.IsA("GuiButton")) {
			warn(`TutorialSkipButton: aucun ${BUTTON_NAME} sous ${ROOT_NAME}`);
			return;
		}
		button.Activated.Connect(() => onSkip());
		connected = true;
	},

	setVisible(visible: boolean): void {
		const frame = findRoot();
		if (frame) frame.Visible = visible;
	},
};
