import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { PopupOrMenuName, TutorialStep } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Surveille la condition de complétion d'un step et appelle onComplete UNE fois.
// Tout est détecté avec ce que le client voit déjà : events serveur → client existants,
// attributs répliqués, et visibilité des frames de InGameUI. Aucun nouvel event.
//
// Le trigger "server" ne branche RIEN : c'est le serveur qui sort du step (run truqué).

const player = Players.LocalPlayer;

function findPopup(name: PopupOrMenuName): GuiObject | undefined {
	const root = TutorialUI.getInGameUI();
	const found = root?.FindFirstChild(name);
	return found?.IsA("GuiObject") ? found : undefined;
}

export const TutorialTriggers = {
	// Retourne la fonction de démontage (à appeler au changement de step).
	watch(step: TutorialStep, onComplete: () => void): () => void {
		const trigger = step.complete;
		let done = false;
		const fire = (): void => {
			if (done) return;
			done = true;
			onComplete();
		};

		if (trigger.kind === "server") {
			return () => {};
		}

		if (trigger.kind === "event") {
			const conn =
				trigger.event === "ButtonTrigger"
					? Events.ButtonTriggerEvent.OnClientEvent.Connect(() => fire())
					: Events.ClaimAcceptedEvent.OnClientEvent.Connect(() => fire());
			return () => conn.Disconnect();
		}

		if (trigger.kind === "attribute") {
			// Seuil RELATIF : un joueur existant a déjà des niveaux, on attend une hausse
			// depuis l'entrée dans le step.
			const baseline = (player.GetAttribute(trigger.attribute) as number | undefined) ?? 0;
			const conn = player.GetAttributeChangedSignal(trigger.attribute).Connect(() => {
				const current = (player.GetAttribute(trigger.attribute) as number | undefined) ?? 0;
				if (current >= baseline + trigger.increaseBy) fire();
			});
			return () => conn.Disconnect();
		}

		// popup / popupClosed — la frame de InGameUI devient visible / invisible.
		const wantVisible = trigger.kind === "popup";
		const frame = findPopup(trigger.popup);
		if (!frame) {
			warn(`TutorialTriggers: frame "${trigger.popup}" introuvable sous InGameUI`);
			return () => {};
		}
		// popupClosed n'est valide qu'après une ouverture : sinon un step attendant la
		// fermeture d'une popup déjà fermée passerait instantanément.
		let seenOpen = frame.Visible;
		const conn = frame.GetPropertyChangedSignal("Visible").Connect(() => {
			if (frame.Visible) {
				seenOpen = true;
				if (wantVisible) fire();
				return;
			}
			if (!wantVisible && seenOpen) fire();
		});
		if (wantVisible && frame.Visible) fire();
		return () => conn.Disconnect();
	},
};
