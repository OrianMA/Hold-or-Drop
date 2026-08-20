import { UserInputService } from "@rbxts/services";
import { dailyRewardKey } from "client/ClientCheatConfig";
import { Events } from "shared/Event";

// Cheat de dev : la touche P fait "avancer d'un jour" la récompense journalière
// (§6.25) — le serveur recule le dernier claim d'une journée, ce qui réarme la
// récompense, fait monter la streak au prochain claim et rouvre le popup.
// Permet de rejouer l'animation et de voir le compteur de jours grimper sans
// attendre minuit UTC.
//
// Activé par `dailyRewardKey` (client/ClientCheatConfig) ET par
// `dailyRewardCheatKey` côté serveur — sans le second, l'event est ignoré.
//
// P et pas une touche du bloc WASD/espace : le déplacement natif pilote la fusée
// pendant un vol (voir RocketSteerController).
//
// ⚠️ Le projet évite d'habitude U/I/O/P (I et O sont le zoom caméra par défaut de
// Roblox et arrivent avec `gameProcessed = true`). P est demandé explicitement, donc
// on ne filtre PAS sur `gameProcessed` — sinon la touche pourrait rester muette si
// Roblox la marque comme traitée. On écarte seulement le cas qui compte vraiment
// ici : le joueur est en train d'écrire dans un champ de texte (chat).

export function init(): void {
	if (!dailyRewardKey) return;

	UserInputService.InputBegan.Connect((input) => {
		if (input.KeyCode !== Enum.KeyCode.P) return;
		if (UserInputService.GetFocusedTextBox() !== undefined) return;
		Events.DailyRewardCheatEvent.FireServer();
	});
}
