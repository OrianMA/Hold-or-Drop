import { Players } from "@rbxts/services";
import { ButtonTriggerService } from "./ButtonTriggerService";
import { ButtonSessionService } from "./ButtonSessionService";
import { UiService } from "./UiService";
import { CharacterService } from "./CharacterService";
import { PlayerDataService } from "./PlayerDataService";
import { MoneyProductService } from "./MoneyProductService";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { BoostService } from "./BoostService";
import { ShopService } from "./ShopService";
import { RebirthService } from "./RebirthService";
import { LeaderboardService } from "./LeaderboardService";
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
	// Robux "buy money" developer products — sets MarketplaceService.ProcessReceipt.
	// Needs PlayerData ready (credits Money on receipt).
	MoneyProductService,
	// Progression must init before RoomService so the BaseCash attribute exists
	// when a room is assigned (the room also listens for later changes).
	PlayerProgressionService,
	// External boosts (group ×2 + money/safety game passes) → input attributes,
	// then recompute. After Progression (needs recompute), before RoomService.
	BoostService,
	// Shop needs PlayerData (money) + PlayerProgression (levels) ready first.
	ShopService,
	// Rebirth: validate + reset. Needs PlayerData (money) + PlayerProgression ready.
	RebirthService,
	// Global leaderboards + podium. Needs PlayerData (Money/Playtime) ready; its
	// refresh loop is self-driven so ordering past PlayerData is not load-bearing.
	LeaderboardService,
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
