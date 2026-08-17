import { Room } from "server/rooms/Room";
import { ScriptedRunHandle, TutorialRunDirector } from "./TutorialRunDirector";
import { TutorialService } from "./TutorialService";

// LA seule API que le jeu de base appelle. Hors tutorial (ou sur un step sans scénario)
// tout renvoie undefined : le jeu garde exactement son comportement normal.
export const TutorialHooks = {
	// Démarre la mise en scène du run si le step courant en porte une.
	beginRun(player: Player, room: Room): ScriptedRunHandle | undefined {
		const step = TutorialService.getCurrentStep(player);
		if (!step || step.run === undefined) return undefined;
		return TutorialRunDirector.begin(player, room, step.run);
	},
};
