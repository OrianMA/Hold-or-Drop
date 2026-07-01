import { GroupService, MarketplaceService, Players } from "@rbxts/services";
import { COMMUNITY, MONEY_TIERS, RESISTANCE_PASS } from "shared/ShopBalance";
import { Events } from "shared/Event";
import { ignoreGamePasses, simulateGamePasses, simulatedOwnedPassIds } from "server/modules/CheatConfig";
import { PlayerProgressionService } from "./PlayerProgressionService";

// HUD flash colours for the community-join feedback (see refreshCommunity).
const JOINED_COLOR = new Color3(0.4, 1, 0.45);
const HINT_COLOR = new Color3(0.6, 0.8, 1);

// Owns detection of EXTERNAL boosts — Roblox group membership + game-pass ownership —
// and writes the input attributes PlayerProgressionService folds into the money
// multiplier / effective base cash.
//
// Game-pass ownership is tracked as a per-player SET of owned pass ids:
//   • seeded once on join (real UserOwnsGamePassAsync, or the CheatConfig simulation);
//   • updated DIRECTLY from PromptGamePassPurchaseFinished using the purchased id.
// We deliberately DO NOT re-query UserOwnsGamePassAsync after a purchase: that call
// caches per session (and a Studio test purchase never grants real ownership), so a
// re-query returns the pre-purchase value and the boost would never apply. Trusting
// the event's id is correct in production AND testable in Studio.

const IN_COMMUNITY_ATTR = "InCommunity";
const MONEY_TIER_MULT_ATTR = "MoneyTierMult";
const HAS_RESISTANCE_PASS_ATTR = "HasResistancePass";

// Per-player set of owned game-pass ids — the session source of truth.
const ownedPasses = new Map<Player, Set<number>>();

function getOwned(player: Player): Set<number> {
	let set = ownedPasses.get(player);
	if (!set) {
		set = new Set<number>();
		ownedPasses.set(player, set);
	}
	return set;
}

// Every real game-pass id the game cares about (id 0 = inert, skipped).
function configuredPassIds(): number[] {
	const ids: number[] = [];
	for (const tier of MONEY_TIERS) if (tier.gamePassId > 0) ids.push(tier.gamePassId);
	if (RESISTANCE_PASS.gamePassId > 0) ids.push(RESISTANCE_PASS.gamePassId);
	return ids;
}

function realOwns(userId: number, gamePassId: number): boolean {
	const [ok, owns] = pcall(() => MarketplaceService.UserOwnsGamePassAsync(userId, gamePassId));
	return ok && owns === true;
}

// Membership check. We use GetGroupsAsync (a web fetch) rather than
// Player:IsInGroup because IsInGroup is cached for the whole session and would
// never reflect a join made mid-session via the native PromptJoinAsync card —
// GetGroupsAsync returns fresh data, so the ×2 can land the moment they join.
// The scan runs inside the pcall so the array stays typed (the pcall result
// itself collapses to unknown).
function isInCommunity(player: Player): boolean {
	const [ok, member] = pcall(() => {
		const groups = GroupService.GetGroupsAsync(player.UserId);
		for (const group of groups) if (group.Id === COMMUNITY.groupId) return true;
		return false;
	});
	return ok && member === true;
}

// Re-derive the boost attributes from the player's owned-pass set (highest money
// tier wins; resistance pass flat add), then fold them into the money multiplier.
function recount(player: Player): void {
	const set = getOwned(player);

	let tierMult = 1;
	for (const tier of MONEY_TIERS) {
		if (tier.gamePassId > 0 && set.has(tier.gamePassId)) tierMult = math.max(tierMult, tier.mult);
	}
	player.SetAttribute(MONEY_TIER_MULT_ATTR, tierMult);
	player.SetAttribute(HAS_RESISTANCE_PASS_ATTR, RESISTANCE_PASS.gamePassId > 0 && set.has(RESISTANCE_PASS.gamePassId));
	PlayerProgressionService.recompute(player);
}

// Synchronous defaults so the attributes exist immediately on join (before the
// async resolve returns) — keeps deriveValues + the client readouts sane.
function setDefaults(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, false);
	player.SetAttribute(MONEY_TIER_MULT_ATTR, 1);
	player.SetAttribute(HAS_RESISTANCE_PASS_ATTR, false);
	PlayerProgressionService.recompute(player);
}

// Full resolve — group membership + game-pass ownership. Yields (web calls); run
// in task.spawn. Seeds the owned-pass set once for the session.
function resolve(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));

	const set = getOwned(player);
	set.clear();
	if (ignoreGamePasses) {
		// CHEAT — start like a player who never owned any game pass: seed nothing,
		// so the set stays empty regardless of real Roblox ownership.
	} else if (simulateGamePasses) {
		// TEST MODE — ignore real Roblox ownership, use the configured simulation.
		for (const id of simulatedOwnedPassIds) set.add(id);
	} else {
		const userId = player.UserId;
		for (const id of configuredPassIds()) if (realOwns(userId, id)) set.add(id);
	}
	recount(player);
}

export const BoostService = {
	init(): void {
		const onAdded = (player: Player): void => {
			setDefaults(player); // sync — attributes exist right away
			task.spawn(() => resolve(player)); // async — web calls
		};
		Players.PlayerAdded.Connect(onAdded);
		for (const player of Players.GetPlayers()) onAdded(player);

		Players.PlayerRemoving.Connect((player) => ownedPasses.delete(player));

		// A successful purchase → record the purchased id DIRECTLY and recompute.
		// The event is the only reliable "just bought" signal (see the file header on
		// why we must NOT re-query UserOwnsGamePassAsync here).
		MarketplaceService.PromptGamePassPurchaseFinished.Connect((player, gamePassId, purchased) => {
			if (!purchased) return;
			getOwned(player).add(gamePassId);
			recount(player);
		});

		// The client opened the native community-join card (GroupService:PromptJoinAsync)
		// and it returned Joined/AlreadyMember. Re-verify server-side and grant the ×2.
		Events.CommunityJoinedEvent.OnServerEvent.Connect((player) => {
			task.spawn(() => BoostService.refreshCommunity(player));
		});
	},

	// Re-check ONLY community membership and grant the ×2 if joined. Fired by the
	// CommunityJoinedEvent handler after the client's native PromptJoinAsync card
	// returns Joined/AlreadyMember. Yields (GetGroupsAsync is a web call).
	//
	// The membership re-check is the security boundary: a faked event still has to
	// pass GetGroupsAsync, so the ×2 is only ever granted to a real member. On
	// success it flashes the green confirmation; if somehow not a member it falls
	// back to the blue join hint.
	refreshCommunity(player: Player): void {
		const wasIn = player.GetAttribute(IN_COMMUNITY_ATTR) === true;
		const isIn = isInCommunity(player);
		player.SetAttribute(IN_COMMUNITY_ATTR, isIn);
		PlayerProgressionService.recompute(player);

		if (isIn && !wasIn) {
			Events.InformationTextEvent.FireClient(player, "Communauté rejointe — x2 argent !", JOINED_COLOR);
		} else if (!isIn) {
			Events.InformationTextEvent.FireClient(
				player,
				"Rejoins la communauté Grorian's Studio pour x2 argent !",
				HINT_COLOR,
			);
		}
	},

	// ── Dev / test helpers (Studio command bar or execute_luau, Server context) ───
	// Simulate ownership changes for a player and apply them immediately — exactly as
	// a real purchase would (same recount path). Use to test the boost/HUD/shop
	// updates when you can't change real ownership (you already own every pass).
	//   local Boost = require(game.ServerScriptService.TS.services.BoostService).BoostService
	//   Boost:devReset(plr)            -- own nothing
	//   Boost:devOwn(plr, 1891624935)  -- simulate buying MONEY x2
	devOwn(player: Player, gamePassId: number): void {
		getOwned(player).add(gamePassId);
		recount(player);
	},
	devDisown(player: Player, gamePassId: number): void {
		getOwned(player).delete(gamePassId);
		recount(player);
	},
	devReset(player: Player): void {
		getOwned(player).clear();
		recount(player);
	},
};
