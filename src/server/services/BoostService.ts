import { MarketplaceService, Players } from "@rbxts/services";
import { COMMUNITY, MONEY_TIERS, SAFETY_PASS } from "shared/ShopBalance";
import { Events } from "shared/Event";
import { simulateGamePasses, simulatedOwnedPassIds } from "server/modules/CheatConfig";
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
const HAS_SAFETY_PASS_ATTR = "HasSafetyPass";

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
	if (SAFETY_PASS.gamePassId > 0) ids.push(SAFETY_PASS.gamePassId);
	return ids;
}

function realOwns(userId: number, gamePassId: number): boolean {
	const [ok, owns] = pcall(() => MarketplaceService.UserOwnsGamePassAsync(userId, gamePassId));
	return ok && owns === true;
}

function isInCommunity(player: Player): boolean {
	const [ok, result] = pcall(() => player.IsInGroup(COMMUNITY.groupId));
	return ok && result === true;
}

// Re-derive the boost attributes from the player's owned-pass set (highest money
// tier wins; safety pass flat add), then fold them into the money multiplier.
function recount(player: Player): void {
	const set = getOwned(player);

	let tierMult = 1;
	for (const tier of MONEY_TIERS) {
		if (tier.gamePassId > 0 && set.has(tier.gamePassId)) tierMult = math.max(tierMult, tier.mult);
	}
	player.SetAttribute(MONEY_TIER_MULT_ATTR, tierMult);
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, SAFETY_PASS.gamePassId > 0 && set.has(SAFETY_PASS.gamePassId));
	PlayerProgressionService.recompute(player);
}

// Synchronous defaults so the attributes exist immediately on join (before the
// async resolve returns) — keeps deriveValues + the client readouts sane.
function setDefaults(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, false);
	player.SetAttribute(MONEY_TIER_MULT_ATTR, 1);
	player.SetAttribute(HAS_SAFETY_PASS_ATTR, false);
	PlayerProgressionService.recompute(player);
}

// Full resolve — group membership + game-pass ownership. Yields (web calls); run
// in task.spawn. Seeds the owned-pass set once for the session.
function resolve(player: Player): void {
	player.SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player));

	const set = getOwned(player);
	set.clear();
	if (simulateGamePasses) {
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
	},

	// Re-check ONLY community membership (the player triggered the CommunityJoinPart
	// prompt). Called by RoomService. Yields.
	//
	// Roblox exposes no in-experience "join group/community" panel API
	// (SocialService/GuiService have no PromptGroupJoin; OpenBrowserWindow is
	// capability-locked to CoreScripts), so this prompt re-checks membership and
	// flashes feedback: a confirmation when the player has just joined (boost
	// unlocked + CommunityJoinController hides the prompt/billboard), or a hint to
	// join otherwise.
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
