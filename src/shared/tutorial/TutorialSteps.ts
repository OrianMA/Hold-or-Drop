import { TutorialStep } from "./TutorialTypes";

// LA liste du tutorial, dans l'ordre. Éditer ici pour changer le déroulé.
// L'`id` est la clé persistée : le renommer renvoie au début les joueurs qui y étaient.
// Voir docs/superpowers/specs/2026-08-17-tutorial-system-design.md §10.
export const TUTORIAL_STEPS: readonly TutorialStep[] = [
	{
		id: "go-to-button",
		text: "Go push your button",
		target: { kind: "world", part: "RoomButton" },
		complete: { kind: "event", event: "ButtonTrigger" },
	},
	{
		id: "press-start",
		text: "Press START to launch your rocket !",
		target: { kind: "gui", path: "ButtonMenu/StartButton" },
		focus: "dim",
		// Le run truqué est porté par le step DEPUIS lequel le décollage part.
		run: {
			freezeAt: 5,
			advanceToOnFreeze: "claim",
			unfreezeOnClaim: true,
			explodeAfterClaim: 2,
			noRisk: true,
		},
		complete: { kind: "popup", popup: "RocketLaunch" },
	},
	{
		id: "watch-launch",
		text: "Your rocket is flying! The higher it goes, the bigger your multiplier",
		target: { kind: "none" },
		complete: { kind: "server" }, // le director saute à "claim" au gel (2,5 s)
	},
	{
		id: "claim",
		text: "Press CLAIM to secure your cash",
		target: { kind: "gui", path: "RocketLaunch/ClaimButtonFrame/ClaimButton" },
		focus: "highlight", // pas de dim : la fusée doit rester visible
		complete: { kind: "event", event: "ClaimAccepted" },
	},
	{
		id: "claim-explode",
		text: "Cash secured! Even if the rocket blows up, you keep it all",
		target: { kind: "none" },
		complete: { kind: "popupClosed", popup: "ButtonFinishGame" },
	},
	{
		id: "go-to-shop",
		text: "Head to the shop to upgrade your rocket",
		target: { kind: "world", part: "Shop" },
		complete: { kind: "popup", popup: "ShopMenu" },
	},
	{
		id: "buy-rocket-speed",
		text: "Buy Rocket Speed: your rocket will climb faster",
		target: { kind: "gui", path: "ShopMenu/Body/ARocketSpeed" },
		focus: "dim",
		// Le panneau ShopMenu occupe y 0.150→0.885 : le bandeau remonte tout en haut,
		// au-dessus du panneau, au lieu de la position par défaut (0.18) qu'il recouvrirait.
		textY: 0.02,
		complete: { kind: "attribute", attribute: "RocketSpeedLevel", increaseBy: 1 },
	},
	{
		id: "back-to-button",
		text: "Go back to your button and play again — you're on your own now!",
		target: { kind: "world", part: "RoomButton" },
		complete: { kind: "event", event: "ButtonTrigger" },
	},
];

export function stepIndexById(id: string): number | undefined {
	for (let i = 0; i < TUTORIAL_STEPS.size(); i++) {
		if (TUTORIAL_STEPS[i].id === id) return i;
	}
	return undefined;
}

export function stepById(id: string): TutorialStep | undefined {
	const index = stepIndexById(id);
	return index !== undefined ? TUTORIAL_STEPS[index] : undefined;
}

export function firstStepId(): string {
	return TUTORIAL_STEPS[0].id;
}
