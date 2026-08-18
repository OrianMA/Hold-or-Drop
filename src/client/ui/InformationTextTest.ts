import { UserInputService } from "@rbxts/services";
import { informationTextKeys } from "client/ClientCheatConfig";
import { InformationText } from "client/ui/InformationText";
import type { InformationRarity } from "shared/InformationRarity";

// Cheat de dev : J / K / L / M affichent un bandeau de test de chaque rareté.
// Activé par `informationTextKeys` dans client/ClientCheatConfig.
// (J-K-L-M et pas U-I-O-P : I et O sont les touches de zoom caméra par défaut
// de Roblox, elles arrivent donc toujours avec gameProcessed = true.)

const KEYS: Array<[Enum.KeyCode, InformationRarity, string]> = [
	[Enum.KeyCode.J, "Common", "Test Commun"],
	[Enum.KeyCode.K, "Rare", "Test Rare"],
	[Enum.KeyCode.L, "Epic", "Test Épique"],
	[Enum.KeyCode.M, "Legendary", "Test Légendaire"],
];

export function init(): void {
	if (!informationTextKeys) return;

	UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		for (const [key, rarity, text] of KEYS) {
			if (input.KeyCode === key) {
				InformationText.show(text, { rarity });
				return;
			}
		}
	});
}
