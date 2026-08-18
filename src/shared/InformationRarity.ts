// ── Raretés de l'InformationText ────────────────────────────────────────────────
// Partagé client/serveur : le serveur choisit la rareté d'un message et la passe
// telle quelle dans InformationTextEvent, le client (client/ui/InformationText)
// la traduit en taille / gradient / son.
//
//   Common    → pas de gradient, taille de base
//   Rare      → RareGradient   (UIGradient posé sur le TextLabel en Studio)
//   Epic      → EpicGradient
//   Legendary → son propre TextLabel (LegendaryText + script RainbowText)

export type InformationRarity = "Common" | "Rare" | "Epic" | "Legendary";

export interface InformationTextOptions {
	// Défaut "Common".
	rarity?: InformationRarity;
	// Couleur du texte. Ignorée dès qu'un gradient s'applique (Rare/Epic) ou en
	// Legendary (le script RainbowText pilote la couleur).
	color?: Color3;
	// Durée à pleine opacité entre le fondu d'entrée et celui de sortie.
	holdSeconds?: number;
}
