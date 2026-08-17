import { TutorialStep } from "./TutorialTypes";

// LA liste du tutorial, dans l'ordre. Éditer ici pour changer le déroulé.
// L'`id` est la clé persistée : le renommer renvoie au début les joueurs qui y étaient.
// Voir docs/superpowers/specs/2026-08-17-tutorial-system-design.md §10.
export const TUTORIAL_STEPS: readonly TutorialStep[] = [
	{
		id: "go-to-button",
		text: "Va appuyer sur ton bouton !",
		target: { kind: "world", part: "RoomButton" },
		complete: { kind: "event", event: "ButtonTrigger" },
	},
	{
		id: "press-start",
		text: "Appuie sur START pour faire décoller ta fusée",
		target: { kind: "gui", path: "ButtonMenu/StartButton" },
		focus: "dim",
		// Bandeau relevé (0.46→0.52) : StartButton commence à y 0.570, ça laisse 0.05 de marge.
		textY: 0.46,
		// Le run truqué est porté par le step DEPUIS lequel le décollage part.
		run: {
			freezeAt: 2.5,
			advanceToOnFreeze: "claim",
			unfreezeOnClaim: true,
			explodeAfterClaim: 1,
			noRisk: true,
		},
		complete: { kind: "popup", popup: "RocketLaunch" },
	},
	{
		id: "watch-launch",
		text: "Ta fusée décolle ! Plus elle monte, plus ton multiplicateur grimpe",
		target: { kind: "none" },
		complete: { kind: "server" }, // le director saute à "claim" au gel (2,5 s)
	},
	{
		id: "claim",
		text: "Appuie sur CLAIM pour sécuriser tes gains",
		target: { kind: "gui", path: "RocketLaunch/ClaimButtonFrame/ClaimButton" },
		focus: "highlight", // pas de dim : la fusée doit rester visible
		complete: { kind: "event", event: "ClaimAccepted" },
	},
	{
		id: "claim-explode",
		text: "Gains sécurisés ! Même si la fusée explose, tu gardes tout",
		target: { kind: "none" },
		complete: { kind: "popupClosed", popup: "ButtonFinishGame" },
	},
	{
		id: "go-to-shop",
		text: "Direction la boutique pour améliorer ta fusée",
		target: { kind: "world", part: "Shop" },
		complete: { kind: "popup", popup: "ShopMenu" },
	},
	{
		id: "buy-rocket-speed",
		text: "Achète Rocket Speed : ta fusée montera plus vite",
		target: { kind: "gui", path: "ShopMenu/Body/ARocketSpeed" },
		focus: "dim",
		// Le panneau ShopMenu occupe y 0.150→0.885 : seule la bande au-dessus reste libre.
		textY: 0.06,
		complete: { kind: "attribute", attribute: "RocketSpeedLevel", increaseBy: 1 },
	},
	{
		id: "back-to-button",
		text: "Retourne à ton bouton et rejoue — à toi de jouer !",
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
