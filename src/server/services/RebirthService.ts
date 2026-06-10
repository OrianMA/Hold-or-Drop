import { Events } from "shared/Event";
import { rebirthCost } from "shared/ShopConfig";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { PlayerDataService } from "./PlayerDataService";

// Authoritative rebirth. The client pre-checks affordability for instant
// feedback, but the reset is fully re-validated here — never trust the client.
// On success: Money → 0, the 3 stat levels → 0, Rebirths += 1 (MultRebirth grows).

const DENIED_COLOR = new Color3(1, 0.4, 0.4);

function handleRebirth(player: Player): void {
	const rebirths = PlayerProgressionService.getRebirths(player);
	const cost = rebirthCost(rebirths);

	if (PlayerDataService.get(player, "Money") < cost) {
		Events.InformationTextEvent.FireClient(player, "Pas assez d'argent pour le Rebirth", DENIED_COLOR);
		return;
	}

	PlayerDataService.set(player, "Money", 0);
	PlayerProgressionService.rebirth(player);
}

export const RebirthService = {
	init(): void {
		Events.RebirthEvent.OnServerEvent.Connect((player) => handleRebirth(player));
	},
};
