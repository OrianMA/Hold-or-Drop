import { Players } from "@rbxts/services";
import { ButtonTriggerService } from "./ButtonTriggerService";
import { ButtonSessionService } from "./ButtonSessionService";
import { UiService } from "./UiService";
import { CharacterService } from "./CharacterService";
import { PlayerDataService } from "./PlayerDataService";
import { PopupConfig } from "server/UI/PopupConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";

export const services: Array<{ init(): void }> = [
	{
		init() {
			UiService.init(PopupConfig);
		},
	},
	PlayerDataService,
	ButtonTriggerService,
	CharacterService,
	EndGameButtonModule,
	{
		// Re-enable the button if a player disconnects mid-game
		init() {
			Players.PlayerRemoving.Connect((player) => {
				ButtonSessionService.cleanup(player);
			});
		},
	},
];
