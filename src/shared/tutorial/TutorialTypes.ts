// Types du système de tutorial. Données pures : aucun import serveur/client, pour que
// les deux côtés lisent la même liste de steps (shared/tutorial/TutorialSteps.ts).

// Cibles monde adressables par un step (résolues côté client).
export type WorldTargetId = "RoomButton" | "Shop";

// Frames de InGameUI dont l'ouverture/fermeture peut valider un step.
export type PopupOrMenuName = "ButtonMenu" | "RocketLaunch" | "ButtonFinishGame" | "ShopMenu";

// Events serveur → client existants que le client sait déjà écouter.
export type TutorialWatchableEvent = "ButtonTrigger" | "ClaimAccepted";

export type TutorialTarget =
	| { readonly kind: "gui"; readonly path: string } // chemin sous InGameUI, ex "ButtonMenu/StartButton"
	| { readonly kind: "world"; readonly part: WorldTargetId }
	| { readonly kind: "none" };

// Comment la cible est mise en avant :
//   "dim"       → overlay sombre troué + blocage (menus : la vue 3D n'a pas d'importance)
//   "highlight" → contour pulsé, SANS assombrir (steps en vol : la fusée doit rester visible)
//   absent      → aucune mise en avant (steps monde : on pointe, on ne masque rien)
export type TutorialFocus = "dim" | "highlight";

export type TutorialTrigger =
	| { readonly kind: "event"; readonly event: TutorialWatchableEvent }
	// Le step passe quand l'attribut a AUGMENTÉ de `increaseBy` depuis l'entrée dans le step
	// (et non quand il atteint une valeur absolue : un joueur existant a déjà des niveaux).
	| { readonly kind: "attribute"; readonly attribute: string; readonly increaseBy: number }
	| { readonly kind: "popup"; readonly popup: PopupOrMenuName } // devient visible
	| { readonly kind: "popupClosed"; readonly popup: PopupOrMenuName } // redevient invisible
	| { readonly kind: "server" }; // le serveur sort lui-même de ce step (run truqué)

// Scénario imposé au run lancé depuis un step. Lu UNE fois, au décollage.
export interface ScriptedRun {
	readonly freezeAt?: number; // gèle l'ascension à t secondes
	readonly advanceToOnFreeze?: string; // step id vers lequel sauter au gel (déterministe)
	readonly unfreezeOnClaim?: boolean; // le claim relance l'ascension
	readonly explodeAfterClaim?: number; // explosion N secondes après le claim
	readonly explodeAt?: number; // explosion à t fixe depuis le décollage
	readonly noRisk?: boolean; // aucun tirage aléatoire : seul le script peut faire exploser
}

export interface TutorialStep {
	readonly id: string; // stable — c'est LUI qui est persisté
	readonly text: string; // instruction affichée (FR)
	readonly target: TutorialTarget;
	readonly focus?: TutorialFocus;
	readonly run?: ScriptedRun;
	readonly complete: TutorialTrigger;
}
