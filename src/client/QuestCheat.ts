import { UserInputService } from "@rbxts/services";
import { questFinishKey } from "client/ClientCheatConfig";
import { Events } from "shared/Event";

// Cheat de dev : la touche U termine une quête disponible (récompense, bandeau Epic
// et pluie d'icônes compris) et crédite 100K ScrollToken, de quoi tester la boutique
// (§6.27) sans farmer.
//
// Activé par `questFinishKey` (client/ClientCheatConfig) ET par `questCheatKey` côté
// serveur — sans le second, l'event est ignoré.
//
// ⚠️ Le projet évite d'habitude U/I/O/P (I et O sont le zoom caméra par défaut de
// Roblox et arrivent avec `gameProcessed = true`). U est demandé explicitement, donc
// on ne filtre PAS sur `gameProcessed` — même raisonnement que la touche P du daily
// (client/DailyRewardCheat) : on écarte seulement le cas qui compte vraiment, le
// joueur en train d'écrire dans un champ de texte.

export function init(): void {
	if (!questFinishKey) return;

	UserInputService.InputBegan.Connect((input) => {
		if (input.KeyCode !== Enum.KeyCode.U) return;
		if (UserInputService.GetFocusedTextBox() !== undefined) return;
		Events.QuestCheatEvent.FireServer();
	});
}
