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
import { DailyRewardService } from "./DailyRewardService";
import { QuestService } from "./QuestService";
import { ScrollShopService } from "./ScrollShopService";
import { LeaderboardService } from "./LeaderboardService";
import { AnalyticsService } from "./AnalyticsService";
import { TutorialService } from "server/tutorial/TutorialService";
import { RoomService } from "server/rooms/RoomService";
import { PopupConfig } from "server/UI/PopupConfig";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";
import { MegaRocketService } from "./MegaRocketService";

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
	// Daily reward: derives the streak → DailyMultiplier / DailyClaimed attributes and
	// grants the cash. Needs PlayerData (streak keys + Money) and PlayerProgression
	// (EffectiveBaseCash) ready.
	DailyRewardService,
	// Quêtes + ScrollToken : progression, versement et publication des attributs
	// Q_<id> / QR_<id>. Needs PlayerData ready (crédite ScrollTokens comme Money).
	QuestService,
	// Global leaderboards + podium. Needs PlayerData (Money/Playtime) ready; its
	// refresh loop is self-driven so ordering past PlayerData is not load-bearing.
	LeaderboardService,
	// Official Roblox analytics (Creator Hub → Analytics). Observational — logs
	// economy/funnel/progression/custom events. Needs PlayerProgression ready
	// (reads isFirstSession for the onboarding funnel gate). No Studio setup.
	AnalyticsService,
	// Tutorial (satellite) — publie l'étape courante via l'attribut TutorialStep.
	// Après PlayerProgression (mêmes attributs lus par les steps), avant RoomService :
	// le premier step cible le bouton dès l'assignation de la room.
	TutorialService,
	RoomService,
	// Binds a ButtonModule per room — must run after RoomService builds them.
	ButtonTriggerService,
	CharacterService,
	EndGameButtonModule,
	// Événement Mega Rocket (toutes les 6 min). Après RoomService : au top de
	// l'événement il repose les fusées au sol, il lui faut donc les rooms construites.
	MegaRocketService,
	// Boutique ScrollToken (§6.27) : dépense les tokens des quêtes. Après
	// MegaRocketService (elle appelle fireNow) et PlayerData/PlayerProgression.
	ScrollShopService,
	{
		// Re-enable the button if a player disconnects mid-game
		init() {
			Players.PlayerRemoving.Connect((player) => {
				ButtonSessionService.cleanup(player);
			});
		},
	},
];
