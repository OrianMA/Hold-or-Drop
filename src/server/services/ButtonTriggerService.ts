import { ButtonModule } from "../modules/ButtonModule";
import { RoomService } from "server/rooms/RoomService";

// Binds the button gameplay to each room. Must init after RoomService (the
// rooms must exist before we attach a ButtonModule to each one).
export const ButtonTriggerService = {
	init(): void {
		for (const room of RoomService.getRooms()) {
			new ButtonModule(room).bind();
		}
	},
};
