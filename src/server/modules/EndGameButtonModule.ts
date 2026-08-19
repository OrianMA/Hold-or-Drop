import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { PopupType } from "shared/PopupType";
import { UiService } from "server/services/UiService";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { PlayerDataService } from "server/services/PlayerDataService";
import { AnalyticsService, TxType } from "server/services/AnalyticsService";

// EndGameButton gameplay state — entered when the player releases the button
// (success / grace-period cancel) or when the player dies from the explosion.
// Coordinates the transition into the ButtonFinishGame popup.

export type EndGameMode = "released" | "killed";

const RELEASE_DELAY = 1; // 1s wait between release and the finish popup
const POST_RESPAWN_DELAY = 0.3; // small grace after respawn so UI doesn't pop in mid-load

// Credited to the player once the client signals the end of the last tween
// (EndGameFinishedEvent). One pending entry per player at most.
//
// `aborted` is set by flush() when another popup opened: the finish popup is then never
// shown (or its animation is cut short client-side), but the entry stays until the client
// confirms the replacement floating text landed — the credit path is the same either way.
// `clientOwes` means the client was told to show something and WILL send back an
// EndGameFinishedEvent — see staleSignals.
interface PendingPayout {
	earned: number;
	aborted: boolean;
	clientOwes: boolean;
	// Analytics itemSku for the economy Source logged when this lands ("ClaimWin" / "LossConsolation").
	itemSku: string;
}

const pending = new Map<Player, PendingPayout>();

// A flushed payout's floating text lives ~1.5 s. If the player squeezes a whole new run
// into that window, its enter() banks the old entry early and the text's late signal
// would land on the NEW payout — crediting it before its animation even runs, which
// leaves the HUD showing double until the next gain. Count those owed-but-obsolete
// signals here and swallow them instead.
const staleSignals = new Map<Player, number>();

// Bank whatever is queued for this player and clear the entry. No-op when nothing is
// pending, so it's safe to call defensively. `superseded` marks the case above: a new
// run replacing an entry whose client visual is still on screen.
function creditPending(player: Player, superseded = false): void {
	const entry = pending.get(player);
	if (!entry) return;
	pending.delete(player);
	if (entry.earned > 0) {
		PlayerDataService.add(player, "Money", entry.earned);
		// Cash faucet: log the gameplay Source with the resulting balance (win / loss reward).
		AnalyticsService.cashSource(
			player,
			entry.earned,
			PlayerDataService.get(player, "Money"),
			TxType.Gameplay,
			entry.itemSku,
		);
	}
	if (superseded && entry.clientOwes) staleSignals.set(player, (staleSignals.get(player) ?? 0) + 1);
}

function waitForRespawn(player: Player): void {
	const character = player.Character;
	const humanoid = character?.FindFirstChildOfClass("Humanoid");
	const alive = character !== undefined && humanoid !== undefined && humanoid.Health > 0;
	if (alive) return;
	player.CharacterAdded.Wait();
	task.wait(POST_RESPAWN_DELAY);
}

export const EndGameButtonModule = {
	// Called from ButtonInGameModule once an outcome is determined.
	// baseCash + multiplier drive the popup animation client-side; earned is the
	// amount we credit when the animation finishes. lossMultiplier is the factor
	// applied to baseCash by the client-side penalty animation before the multiplier
	// drain — always 1 now (a losing explosion uses enterRewardOnly, no popup), but
	// kept so the client penalty branch (lossMultiplier < 1) stays supported.
	// claimBonus is the Perfect/Critical Claim factor (1 when neither rolled): the popup
	// grows baseCash by it BEFORE applying the multiplier, so the player sees which value
	// the bonus actually boosted.
	enter(
		player: Player,
		mode: EndGameMode,
		baseCash: number,
		multiplier: number,
		earned: number,
		lossMultiplier: number,
		claimBonus: number,
	): void {
		ButtonSessionService.cleanup(player);
		UiService.HideCurrent(player);

		// A flushed payout from the previous run may still be waiting for its client
		// signal (the player can start and finish a new run in the meantime) — bank it
		// now instead of losing it when we overwrite the entry.
		creditPending(player, true);

		const entry: PendingPayout = { earned, aborted: false, clientOwes: false, itemSku: "ClaimWin" };
		pending.set(player, entry);

		task.spawn(() => {
			if (mode === "released") {
				task.wait(RELEASE_DELAY);
			} else {
				waitForRespawn(player);
			}

			// Player may have disconnected while we were waiting
			if (player.Parent === undefined) {
				if (pending.get(player) === entry) pending.delete(player);
				return;
			}

			// A popup opened (or a rebirth landed) while we waited → the finish screen is
			// off the table. flush() already sent the replacement floating text.
			if (entry.aborted || pending.get(player) !== entry) return;

			entry.clientOwes = true; // the animation will signal back when it ends
			UiService.Show(player, PopupType.ButtonFinishGame);
			Events.EndGameStartEvent.FireClient(player, baseCash, multiplier, lossMultiplier, claimBonus);
		});
	},

	// Called from UiService.Show for ANY popup other than ButtonFinishGame. A payout
	// still waiting to be shown — or a finish animation already playing — is dropped: no
	// popup and no HUD restore, so the screen the player just opened keeps the focus. The
	// gain is shown instead as a single floating text client-side, which fires
	// EndGameFinishedEvent when it fades so the credit below still lands in full.
	flush(player: Player): void {
		const entry = pending.get(player);
		if (!entry || entry.aborted) return;
		entry.aborted = true;

		// Nothing was won → just drop the finish screen, no floating text.
		if (entry.earned <= 0) {
			pending.delete(player);
			return;
		}

		entry.clientOwes = true; // the floating text will signal back when it fades
		Events.EndGamePayoutFlushEvent.FireClient(player, entry.earned);
	},

	// Losing explosion: no ButtonFinishGame popup. The player gets a flat consolation
	// (baseCash / 3) shown as a single jumping text that flies into the money HUD
	// (client LossRewardBehavior). We reuse the same pending-credit path as the popup:
	// the client fires EndGameFinishedEvent once the text lands, and the init() handler
	// below credits `reward` and reconciles the HUD counter — no double count.
	enterRewardOnly(player: Player, reward: number): void {
		ButtonSessionService.cleanup(player);
		UiService.HideCurrent(player); // hide the RocketLaunch popup (no finish popup opens)

		creditPending(player, true);
		pending.set(player, { earned: reward, aborted: false, clientOwes: true, itemSku: "LossConsolation" });
		Events.LossRewardEvent.FireClient(player, reward);
	},

	// Drop any queued payout for this player and hide the finish popup. Called on a
	// NORMAL rebirth (RebirthService): a run whose floating texts are still animating
	// would otherwise fire EndGameFinishedEvent and credit `earned` AFTER Money was
	// reset to 0. Clearing the entry means that late credit adds nothing.
	cancelPending(player: Player): void {
		// Mark before dropping so a still-waiting enter() task bails instead of opening
		// the popup on a balance that was just reset to 0.
		const entry = pending.get(player);
		if (entry) entry.aborted = true;
		pending.delete(player);
		staleSignals.delete(player);
		UiService.Hide(player, PopupType.ButtonFinishGame);
	},

	// Wired by services/index.ts so the popup hides once the client animation finishes
	init(): void {
		// Any other popup opening converts a pending payout into a floating text.
		UiService.SetBeforeShow((player) => EndGameButtonModule.flush(player));

		Events.EndGameFinishedEvent.OnServerEvent.Connect((player) => {
			// Late signal from a payout already banked by the next run — drop it so it
			// doesn't credit (and close) the payout that replaced it.
			const stale = staleSignals.get(player) ?? 0;
			if (stale > 0) {
				staleSignals.set(player, stale - 1);
				return;
			}

			creditPending(player);
			UiService.Hide(player, PopupType.ButtonFinishGame);
		});

		Players.PlayerRemoving.Connect((player) => {
			pending.delete(player);
			staleSignals.delete(player);
		});
	},
};
