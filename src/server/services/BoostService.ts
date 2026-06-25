import { MarketplaceService, Players } from "@rbxts/services";
import { COMMUNITY, MONEY_TIERS, SAFETY_PASS } from "shared/ShopBalance";
import { PlayerProgressionService } from "./PlayerProgressionService";

// Owns detection of EXTERNAL boosts — Roblox group membership + game-pass
// ownership — and writes the input attributes PlayerProgressionService folds into
// the money multiplier / effective base cash. Web calls (IsInGroup,
// UserOwnsGamePassAsync) yield and can fail, so each is pcall-guarded. A game-pass
// id of 0 is INERT (no web call, treated not-owned) until a real id is configured.

const IN_COMMUNITY_ATTR = "InCommunity";
const MONEY_TIER_MULT_ATTR = "MoneyTierMult";
const HAS_SAFETY_PASS_ATTR = "HasSafetyPass";

function ownsGamePass(userId: number, gamePassId: number): boolean {
	if (gamePassId <= 0) return false; // inert until a real id is set
	const [ok, owns] = pcall(() => MarketplaceService.UserOwnsGamePassAsync(userId, gamePassId));
	return ok && owns === true;
}

// Highest owned money tier's multiplier (ladder — top tier wins). 1 if none.
// Iterate high → low and return on the first owned tier: stops early and makes
// at most one extra web call once an owned tier is found (id-0 tiers are skipped
// by ownsGamePass without any web call).
function resolveTierMult(userId: number): number {
	for (let i = MONEY_TIERS.size() - 1; i >= 0; i--) {
		const tier = MONEY_TIERS[i];
		if (ownsGamePass(userId, tier.gamePassId)) return tier.mult;
	}
	return 1;
}

function isInCommunity(player: Player): boolean {
	const [ok, result] = pcall(() => player.IsInGroup(COMMUNITY.groupId));
	return ok && result === true;
}

// Synchronous defaults so the attributes exist immediately on join (before the
// async web calls return) — keeps deriveValues + the client shop readout sane.
function setDefaults(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, false);
	player.SetAttribute(MONEY_TIER_MULT_ATTR, 1);
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, false);
	PlayerProgressionService.recompute(player);
}

// Full resolve — group + all game passes. Yields (web calls); run in task.spawn.
function resolve(player: Player): void {
	const userId = player.UserId;
	player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));
	player.SetAttribute(MONEY_TIER_MULT_ATTR, resolveTierMult(userId));
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, ownsGamePass(userId, SAFETY_PASS.gamePassId));
	PlayerProgressionService.recompute(player);
}

export const BoostService = {
	init(): void {
		const onAdded = (player: Player): void => {
			setDefaults(player); // sync — attributes exist right away
			task.spawn(() => resolve(player)); // async — web calls
		};
		Players.PlayerAdded.Connect(onAdded);
		for (const player of Players.GetPlayers()) onAdded(player);

		// A successful game-pass purchase → re-resolve that player's ownership.
		MarketplaceService.PromptGamePassPurchaseFinished.Connect((player, _gamePassId, purchased) => {
			if (purchased) task.spawn(() => resolve(player));
		});
	},

	// Re-check ONLY community membership (the player joined the group then
	// triggered the CommunityJoinPart prompt). Called by RoomService. Yields.
	refreshCommunity(player: Player): void {
		player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));
		PlayerProgressionService.recompute(player);
	},
};
