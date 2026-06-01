import { Players } from "@rbxts/services";
import { ButtonTriggerService } from "./ButtonTriggerService";
import { ButtonSessionService } from "./ButtonSessionService";
import { UiService } from "./UiService";
import { CharacterService } from "./CharacterService";
import { PlayerDataService } from "./PlayerDataService";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { RoomService } from "server/rooms/RoomService";
import { PopupConfig } from "server/UI/PopupConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";

export const services: Array<{ init(): void }> = [
	{
		init() {
			UiService.init(PopupConfig);
		},
	},
	PlayerDataService,
	// Progression must init before RoomService so the BaseCash attribute exists
	// when a room is assigned (the room also listens for later changes).
	PlayerProgressionService,
	RoomService,
	// Binds a ButtonModule per room — must run after RoomService builds them.
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
