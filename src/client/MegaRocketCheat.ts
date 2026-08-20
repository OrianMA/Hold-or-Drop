import { UserInputService } from "@rbxts/services";
import { megaRocketKey } from "client/ClientCheatConfig";
import { Events } from "shared/Event";

// Cheat de dev : la touche G ramène le compte à rebours de la Mega Rocket (§6.24)
// à 3 s, pour déclencher l'événement à la demande sans attendre les 6 minutes.
// Activé par `megaRocketKey` (client/ClientCheatConfig) ET par
// `megaRocketCheatKey` côté serveur — sans le second, l'event est ignoré.
//
// (G et pas une touche du bloc WASD/espace : le déplacement natif pilote la fusée
// pendant un vol, voir RocketSteerController.)

export function init(): void {
	if (!megaRocketKey) return;

	UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode !== Enum.KeyCode.G) return;
		Events.MegaRocketCheatEvent.FireServer();
	});
}
