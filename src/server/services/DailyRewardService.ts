import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import {
	DAILY_AUTO_OPEN_ATTR,
	DAILY_CLAIMED_ATTR,
	DAILY_MULTIPLIER_ATTR,
	DAILY_X3_MULTIPLIER,
	dailyMultiplier,
	dayIndex,
} from "shared/DailyRewardConfig";
import { PlayerDataService } from "./PlayerDataService";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { AnalyticsService, TxType } from "./AnalyticsService";
import { TutorialService } from "server/tutorial/TutorialService";
import { dailyRewardCheatKey } from "server/modules/CheatConfig";

// Authoritative daily reward. Coming back N days in a row pays
// `EffectiveBaseCash × N` — the Robux "3X Claim" product triples that total.
//
// State lives in PlayerDataService (same store, no migration — the two keys default
// to 0 for existing saves, exactly like Playtime did):
//   DailyStreak    — consecutive days already CLAIMED (0 = never)
//   DailyLastClaim — UTC day index of the last claim (0 = never)
//
// From those two the service derives and publishes two replicated attributes the
// client reads directly, so the popup needs no round-trip to render:
//   DailyMultiplier — what a claim would apply right now
//   DailyClaimed    — today's reward already taken
//   DailyAutoOpen   — the popup must show itself (see the auto-open rules below)
//
// The client is never trusted: it only asks (DailyRewardClaimEvent), the streak and
// the day boundary are re-derived here on every grant.

const STREAK_KEY = "DailyStreak";
const LAST_CLAIM_KEY = "DailyLastClaim";

// PlayerDataService writes its attributes after an async DataStore load; give it a
// bounded window rather than reading a nil attribute as "never claimed" (which would
// hand out a second reward and reset the streak).
const LOAD_TIMEOUT = 30;
const LOAD_POLL = 0.1;

// Auto-open rules — the gate is the TUTORIAL, not the account age:
//   • tutorial running (a brand-new player, a resumed tutorial, or the forceTutorial
//     cheat): the popup is DEFERRED to the first rebirth AFTER the tutorial ends. It
//     must never land on top of the onboarding, whatever put the player there;
//   • anybody else joining with a pending reward: the popup opens right away.
// Deferred players sit in this set until they rebirth (tutorial over) or leave.
const deferredToRebirth = new Set<Player>();

// TutorialService publishes this attribute at the end of its own async load — before
// that, isActive() would answer "false" simply because the state isn't in yet, and the
// popup would race the tutorial it is supposed to avoid.
const TUTORIAL_STEP_ATTR = "TutorialStep";

// The streak a claim would commit right now: +1 when the last claim was yesterday,
// back to 1 otherwise (a missed day breaks the chain). Already claimed today → the
// stored streak, unchanged.
function pendingStreak(player: Player): number {
	const streak = PlayerDataService.get(player, STREAK_KEY);
	const last = PlayerDataService.get(player, LAST_CLAIM_KEY);
	const today = dayIndex(os.time());

	if (last === today) return math.max(1, streak);
	if (last === today - 1) return streak + 1;
	return 1;
}

function hasClaimedToday(player: Player): boolean {
	return PlayerDataService.get(player, LAST_CLAIM_KEY) === dayIndex(os.time());
}

// Re-derives the two published attributes from the stored state. Called on join, on
// every grant, and whenever the popup state could have gone stale.
function publish(player: Player): void {
	player.SetAttribute(DAILY_MULTIPLIER_ATTR, dailyMultiplier(pendingStreak(player)));
	player.SetAttribute(DAILY_CLAIMED_ATTR, hasClaimedToday(player));
}

// Demande au client d'ouvrir le popup : on incrémente le compteur, il ouvre dès qu'il
// voit une valeur plus haute que la dernière traitée (voir DAILY_AUTO_OPEN_ATTR).
function requestOpen(player: Player): void {
	const current = (player.GetAttribute(DAILY_AUTO_OPEN_ATTR) as number | undefined) ?? 0;
	player.SetAttribute(DAILY_AUTO_OPEN_ATTR, current + 1);
}

// Ouverture à la CONNEXION : seulement si la récompense du jour est encore à prendre.
// Le cheat (§9) est la seule dérogation, et il ne vaut QUE pour cette porte d'entrée —
// le rebirth, lui, teste `hasClaimedToday` sans exemption (voir onRebirth).
function shouldOpenOnJoin(player: Player): boolean {
	return !hasClaimedToday(player) || dailyRewardCheatKey;
}

// Credits the cash and reports it. `multiplier` is the streak multiplier, `bonus` the
// product factor (1 or 3) — kept apart so the client can show which one paid.
function payout(player: Player, multiplier: number, bonus: number): number {
	const baseCash = PlayerProgressionService.get(player, "EffectiveBaseCash");
	const amount = math.floor(baseCash * multiplier * bonus);
	if (amount <= 0) return 0;

	PlayerDataService.add(player, "Money", amount);

	// Analytics: a faucet — cash entering the economy. Robux-paid claims are tagged
	// IAP so the free and the ×3 paths stay separable on the dashboard.
	AnalyticsService.cashSource(
		player,
		amount,
		PlayerDataService.get(player, "Money"),
		bonus > 1 ? TxType.IAP : TxType.Gameplay,
		`DailyReward_x${multiplier}`,
	);
	AnalyticsService.custom(player, bonus > 1 ? "DailyRewardClaimedX3" : "DailyRewardClaimed", multiplier);

	Events.DailyRewardGrantedEvent.FireClient(player, amount, multiplier, bonus);
	return amount;
}

// Commits today's claim: stores the new streak + today's day index.
function commit(player: Player, streak: number): void {
	PlayerDataService.set(player, STREAK_KEY, streak);
	PlayerDataService.set(player, LAST_CLAIM_KEY, dayIndex(os.time()));
	deferredToRebirth.delete(player); // plus rien à ouvrir aujourd'hui
}

function handleClaim(player: Player): void {
	if (hasClaimedToday(player)) return; // already taken today — ignore (client also blocks)

	const streak = pendingStreak(player);
	const multiplier = dailyMultiplier(streak);
	commit(player, streak);
	publish(player);
	payout(player, multiplier, 1);
}

export const DailyRewardService = {
	init(): void {
		const onAdded = (player: Player): void => {
			player.SetAttribute(DAILY_AUTO_OPEN_ATTR, 0); // sync default — jamais de nil côté client
			task.spawn(() => {
				if (!DailyRewardService.waitForData(player)) return;
				publish(player);
				if (!shouldOpenOnJoin(player)) return;
				// The tutorial owns the screen — wait for the first rebirth after it ends.
				if (TutorialService.isActive(player)) deferredToRebirth.add(player);
				else requestOpen(player);
			});
		};
		Players.PlayerAdded.Connect(onAdded);
		for (const player of Players.GetPlayers()) onAdded(player);

		Players.PlayerRemoving.Connect((player) => deferredToRebirth.delete(player));

		Events.DailyRewardClaimEvent.OnServerEvent.Connect((player) => handleClaim(player));

		// CHEAT — inerte en production : sans le flag serveur, l'event est ignoré même
		// si un client le tire.
		if (dailyRewardCheatKey) {
			Events.DailyRewardCheatEvent.OnServerEvent.Connect((player) => DailyRewardService.devAdvanceDay(player));
		}
	},

	// Blocks until PlayerDataService has published the daily keys (its DataStore load
	// is async). False if the player left or the load never landed — the caller must
	// then do nothing rather than act on defaults.
	waitForData(player: Player): boolean {
		const deadline = os.clock() + LOAD_TIMEOUT;
		while (
			player.GetAttribute(LAST_CLAIM_KEY) === undefined ||
			player.GetAttribute(TUTORIAL_STEP_ATTR) === undefined
		) {
			if (player.Parent === undefined) return false;
			if (os.clock() > deadline) {
				warn(`DailyRewardService: player/tutorial data never loaded for ${player.Name}`);
				return false;
			}
			task.wait(LOAD_POLL);
		}
		return true;
	},

	// Paid "3X Claim" — granted from MoneyProductService.ProcessReceipt.
	// If today's free reward was already taken (a purchase racing the free claim, or a
	// second purchase), the streak is already committed: we still pay the ×3 on the same
	// day's multiplier rather than swallowing a purchase the player paid Robux for.
	claimPaid(player: Player): void {
		const streak = pendingStreak(player);
		const multiplier = dailyMultiplier(streak);

		if (!hasClaimedToday(player)) {
			commit(player, streak);
			publish(player);
		}
		payout(player, multiplier, DAILY_X3_MULTIPLIER);
	},

	// Called by RebirthService after a successful rebirth. Only meaningful for a player
	// whose popup was deferred on join because the tutorial was running. A tutorial still
	// in progress keeps the deferral — the popup waits for a rebirth made OUTSIDE the
	// onboarding. A no-op for everyone else.
	//
	// Le test `hasClaimedToday` est STRICT ici, cheat compris : rebirther ne redonne pas
	// une récompense déjà prise, donc il n'y a rien à afficher. Le popup du rebirth est
	// réservé au joueur qui n'a pas encore réclamé.
	onRebirth(player: Player): void {
		if (!deferredToRebirth.has(player)) return;
		if (TutorialService.isActive(player)) return;
		deferredToRebirth.delete(player);
		if (!hasClaimedToday(player)) requestOpen(player);
	},

	// True while today's reward is still up for grabs (read by the auto-open rules).
	isPending(player: Player): boolean {
		return !hasClaimedToday(player);
	},

	// ── Dev / test helpers (Studio command bar or execute_luau, Server context) ───
	// The streak only moves once a real UTC day passes, so it is otherwise untestable
	// without waiting 24h. Same spirit as BoostService.devOwn — they go through the
	// normal publish path, so the popup reacts exactly as it would in production.
	//   local Daily = require(game.ServerScriptService.TS.services.DailyRewardService).DailyRewardService
	//   Daily:devSetStreak(plr, 4, 1)  -- 4 days claimed, the last one YESTERDAY → next claim ×5
	//   Daily:devReset(plr)            -- never claimed → next claim ×1
	devSetStreak(player: Player, streak: number, daysAgo: number): void {
		PlayerDataService.set(player, STREAK_KEY, math.max(0, math.floor(streak)));
		PlayerDataService.set(player, LAST_CLAIM_KEY, dayIndex(os.time()) - math.max(0, math.floor(daysAgo)));
		publish(player);
		if (!hasClaimedToday(player)) requestOpen(player);
	},
	// Simule le passage au lendemain SANS toucher à l'horloge : le dernier claim est
	// reculé d'une journée. La récompense redevient donc disponible et la streak
	// avancera de 1 au prochain claim — appuyer deux fois sans réclamer entre les deux
	// casse la série, exactement comme deux vraies journées manquées.
	devAdvanceDay(player: Player): void {
		const today = dayIndex(os.time());
		const last = PlayerDataService.get(player, LAST_CLAIM_KEY);
		PlayerDataService.set(player, LAST_CLAIM_KEY, (last > 0 ? last : today) - 1);
		publish(player);
		requestOpen(player); // le compteur monte → le client rouvre le popup
	},
	devReset(player: Player): void {
		PlayerDataService.set(player, STREAK_KEY, 0);
		PlayerDataService.set(player, LAST_CLAIM_KEY, 0);
		publish(player);
		requestOpen(player);
	},
};
