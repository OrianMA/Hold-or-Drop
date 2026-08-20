import { Events } from "shared/Event";
import { rebirthCost } from "shared/ShopConfig";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { PlayerDataService } from "./PlayerDataService";
import { DailyRewardService } from "./DailyRewardService";
import { AnalyticsService, TxType } from "./AnalyticsService";
import { RoomService } from "server/rooms/RoomService";
import { RocketPlacer } from "server/modules/RocketPlacer";
import { EndGameButtonModule } from "server/modules/EndGameButtonModule";

// Authoritative rebirth. The client pre-checks affordability for instant
// feedback, but the reset is fully re-validated here — never trust the client.
// On success: Money → 0, the 3 stat levels → 0, Rebirths += 1 (MultRebirth grows).
// Playtime is NEVER touched here — it drives the leaderboard and must survive rebirths.

const DENIED_COLOR = new Color3(1, 0.4, 0.4);

function handleRebirth(player: Player): void {
	const rebirths = PlayerProgressionService.getRebirths(player);
	const cost = rebirthCost(rebirths);

	const money = PlayerDataService.get(player, "Money");
	if (money < cost) {
		Events.InformationTextEvent.FireClient(player, "Pas assez d'argent pour le Rebirth", { color: DENIED_COLOR });
		return;
	}

	PlayerDataService.set(player, "Money", 0);
	PlayerProgressionService.rebirth(player);

	// Analytics: the whole balance leaves the economy (Sink → 0) + progression milestone
	// + custom counter + onboarding step 5. Read the fresh rebirth count for the level.
	const newRebirths = PlayerProgressionService.getRebirths(player);
	AnalyticsService.cashSink(player, money, 0, TxType.Rebirth, `Rebirth${newRebirths}`);
	AnalyticsService.rebirth(player, newRebirths);
	AnalyticsService.custom(player, "RebirthDone", newRebirths);
	AnalyticsService.onboardingStep(player, 5, "Rebirth");

	// Drop any payout that was still animating: cancel the server credit so it can't
	// land after the reset to 0, and tell the client to remove the in-flight floating
	// texts flying toward the money HUD (FloatingCash).
	EndGameButtonModule.cancelPending(player);
	Events.RebirthResetEvent.FireClient(player);

	// The rebirth level just changed → swap the pad rocket for the new one instantly
	// (otherwise the old rocket would linger until the player leaves/rejoins the room).
	const room = RoomService.getRoom(player);
	if (room) RocketPlacer.place(room);

	// A brand-new player had their daily reward popup deferred (the tutorial owned the
	// screen on join) — their first rebirth is where it finally shows. No-op otherwise.
	DailyRewardService.onRebirth(player);
}

export const RebirthService = {
	init(): void {
		Events.RebirthEvent.OnServerEvent.Connect((player) => handleRebirth(player));
	},

	// Safe rebirth — paid via the Robux dev product (SAFE_REBIRTH_PRODUCT_ID),
	// granted from MoneyProductService.ProcessReceipt. Increments Rebirths but keeps
	// ALL progression (Money + stat levels untouched), then swaps the pad rocket to
	// the new rebirth level like a normal rebirth.
	safeRebirth(player: Player): void {
		PlayerProgressionService.safeRebirth(player);

		// Analytics: progression milestone + custom counter (Robux-paid, keeps progression).
		const newRebirths = PlayerProgressionService.getRebirths(player);
		AnalyticsService.rebirth(player, newRebirths);
		AnalyticsService.custom(player, "SafeRebirthDone", newRebirths);

		// Swap the pad rocket for the new rebirth-level one. Wrapped in pcall: this
		// runs inside ProcessReceipt, and a throw AFTER the Rebirths increment would
		// make Roblox retry the receipt → double rebirth. The swap is cosmetic, so a
		// failure here must never undo (or duplicate) the grant.
		const room = RoomService.getRoom(player);
		if (room) pcall(() => RocketPlacer.place(room));
	},
};
