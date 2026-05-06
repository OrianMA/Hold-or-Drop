import { Players } from "@rbxts/services";
import { ButtonTriggerService } from "./ButtonTriggerService";
import { ButtonSessionService } from "./ButtonSessionService";
import { UiService } from "./UiService";
import { PopupConfig } from "server/UI/PopupConfig";

export const services: Array<{ init(): void }> = [
	{
		init() {
			UiService.init(PopupConfig);
		},
	},
	ButtonTriggerService,
	{
		// Re-enable the button if a player disconnects mid-game
		init() {
			Players.PlayerRemoving.Connect((player) => {
				ButtonSessionService.cleanup(player);
			});
		},
	},
];
