// ── Mega Rocket ───────────────────────────────────────────────────────────────
// Événement global : toutes les MEGA_ROCKET_INTERVAL secondes, TOUS les joueurs
// reçoivent une « Mega Rocket » — une fusée arc-en-ciel, légèrement plus grande,
// qui paie MEGA_ROCKET_BASE_CASH_MULT × le base cash sur SON vol. Une seule par
// événement : elle est consommée par le vol qui la décolle.
//
// L'état tient dans un simple attribut joueur (répliqué, pas de RemoteEvent) :
//   • serveur — MegaRocketService le pose au top de l'événement, RocketPlacer en
//     déduit les visuels, ButtonInGameModule le multiplicateur de base cash ;
//   • client  — RocketLaunchBehavior applique le même ×8 à l'aperçu de gain.
//
// Les visuels arc-en-ciel eux-mêmes passent par un tag CollectionService posé sur
// le modèle `Rocket` (le serveur ne fait que le poser, le client l'anime).

export const MEGA_ROCKET_INTERVAL = 360; // 6 min entre deux événements
export const MEGA_ROCKET_BASE_CASH_MULT = 8;
// FACTEUR appliqué à l'échelle authored du template (qui n'est pas 1 partout —
// RocketLvl2 est à 1.5), pas une échelle absolue. Voir RocketPlacer.
export const MEGA_ROCKET_SCALE = 1.15; // « légèrement » plus grande

export const MEGA_ROCKET_ATTR = "MegaRocket"; // attribut joueur (répliqué)
export const MEGA_ROCKET_TAG = "MegaRocket"; // CollectionService, sur le modèle Rocket
// CollectionService, posé EN STUDIO sur Workspace/Environment/DisplayEventPanel/
// SurfaceGui/MegaRocketFrame (le fond du compte à rebours). Le client l'anime aux
// mêmes couleurs que les fusées ; le tag évite un chemin en dur et gère le
// streaming in/out du panneau tout seul.
export const MEGA_ROCKET_PANEL_TAG = "MegaRocketPanel";

// Bandeau Legendary diffusé à tout le monde au déclenchement (InformationTextEvent).
export const MEGA_ROCKET_ANNOUNCE = "MEGA ROCKET APPEARS  CASH ×8";

// Panneau Workspace/Environment/DisplayEventPanel : texte affiché quelques
// secondes au déclenchement, à la place du compte à rebours.
export const MEGA_ROCKET_PANEL_FIRED = "MEGA ROCKET !";

// "Mega Rocket in : 05:23 min"
export function megaRocketPanelText(secondsLeft: number): string {
	const total = math.max(0, math.floor(secondsLeft));
	return string.format("Mega Rocket in : %02d:%02d min", math.floor(total / 60), total % 60);
}

// Le joueur a-t-il une Mega Rocket en cours (sur le pad ou en vol) ?
// Lecture pure d'attribut — utilisable des deux côtés.
export function hasMegaRocket(player: Player): boolean {
	return player.GetAttribute(MEGA_ROCKET_ATTR) === true;
}
