import { AnalyticsService as RobloxAnalytics, HttpService, Players } from "@rbxts/services";
import { PlayerProgressionService } from "./PlayerProgressionService";
import { PlayerDataService } from "./PlayerDataService";

// Thin, crash-proof wrapper around Roblox's official AnalyticsService (Creator Hub →
// Analytics). NOTHING here needs any Studio setup — the events flow to the dashboard
// automatically for a published experience (first data lands after ~24h).
//
// Design rules:
//   • Every Roblox analytics call is wrapped in pcall — analytics can throttle or be
//     disabled, and it must NEVER break gameplay. A failed log is silently dropped.
//   • Server-only. Gameplay is server-authoritative, so every economy/progression
//     event is logged from the server at the exact point state truly changes.
//   • Semantic helpers (cashSource/cashSink/runStep/…) so call sites stay one-liners.
//
// Event map:
//   Economy  → cash earned (Source) / spent (Sink): gameplay payouts, shop, rebirth, IAP.
//   Funnel   "CoreRun"  → per-run progress: Launch → Claim → Banked (repeatable).
//   Onboarding funnel   → first-session only: Joined → Launch → Claim → Purchase → Rebirth.
//   Progression "Rebirth" → each rebirth completed (level = rebirth count).
//   Custom   → per-event counters with up to 3 breakdown fields (RocketLaunched, …).
//
// Naming convention for custom events: <Subject><PastTenseVerb> in PascalCase, one
// event per real-world fact (RocketLaunched, QuestCompleted, DailyRewardClaimed).
// A VARIANT of a fact is a breakdown FIELD, never a second event name — that's what
// makes a percentage readable on the dashboard (e.g. RunClaimed × Perfect/Standard).

const CURRENCY = "Cash";

// Recommended transactionType buckets (free strings on the API; kept consistent here).
export const TxType = {
	Gameplay: "Gameplay",
	Shop: "Shop",
	Rebirth: "Rebirth",
	IAP: "IAP",
} as const;

// The 3 custom-field slots the dashboard exposes for breakdowns.
const FIELD_KEYS = [
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
] as const;

// Builds the customFields object (or undefined) from up to 3 positional values.
function buildFields(...values: Array<string | number | undefined>): object | undefined {
	const fields: { [key: string]: string | number } = {};
	let any = false;
	for (let i = 0; i < values.size() && i < FIELD_KEYS.size(); i++) {
		const v = values[i];
		if (v !== undefined) {
			fields[FIELD_KEYS[i]] = v;
			any = true;
		}
	}
	return any ? fields : undefined;
}

// Onboarding steps already sent this session (per player) — a step is logged at most once.
const onboardingSent = new Map<Player, Set<number>>();

// Snapshot taken at join: persisted Playtime (seconds, all previous sessions) and the
// os.clock() of the join. `playedSeconds` = snapshot + elapsed session time.
// Why not read the Playtime attribute directly? LeaderboardService only folds the
// session into it every flush, so a direct read lags by up to one flush interval.
const playtimeAtJoin = new Map<Player, number>();
const joinClock = new Map<Player, number>();

// One funnel step, whatever the funnel. pcall'd: throttled analytics must never break
// gameplay.
function logFunnelStep(player: Player, funnelName: string, sessionId: string, step: number, stepName: string): void {
	pcall(() => RobloxAnalytics.LogFunnelStepEvent(player, funnelName, sessionId, step, stepName));
}

export const AnalyticsService = {
	init(): void {
		const onJoin = (player: Player): void => {
			joinClock.set(player, os.clock());
			task.spawn(() => {
				// Wait until progression finished loading (it sets Rebirths at the end of
				// the async load), so isFirstSession is decided before the join step.
				if (player.GetAttribute("Rebirths") === undefined) {
					player.GetAttributeChangedSignal("Rebirths").Wait();
				}
				// Same for the persisted Playtime (PlayerDataService writes every numeric
				// key once its load finishes) — the baseline of `playedSeconds`.
				if (player.GetAttribute("Playtime") === undefined) {
					player.GetAttributeChangedSignal("Playtime").Wait();
				}
				playtimeAtJoin.set(player, PlayerDataService.get(player, "Playtime"));
				AnalyticsService.onboardingStep(player, 1, "Joined");
			});
		};
		Players.PlayerAdded.Connect(onJoin);
		for (const player of Players.GetPlayers()) onJoin(player);

		Players.PlayerRemoving.Connect((player) => {
			onboardingSent.delete(player);
			playtimeAtJoin.delete(player);
			joinClock.delete(player);
		});
	},

	// Total seconds this player has EVER played, live (previous sessions + this one).
	// Used as the clock of "time to first X" metrics, so they stay correct for a player
	// who reaches the milestone several sessions after joining.
	playedSeconds(player: Player): number {
		const previous = playtimeAtJoin.get(player) ?? PlayerDataService.get(player, "Playtime");
		const session = os.clock() - (joinClock.get(player) ?? os.clock());
		return math.floor(previous + session);
	},

	// ── Run funnel (repeatable, one funnelSessionId per run) ────────────────────
	// A fresh, unique id for one run of the core loop (Launch → Claim → Banked).
	newRunId(): string {
		const [ok, id] = pcall(() => HttpService.GenerateGUID(false));
		return ok ? (id as string) : `${tick()}`;
	},

	// Generic funnel (any funnel name) — used by the tutorial.
	funnelStep(player: Player, funnelName: string, sessionId: string, step: number, stepName: string): void {
		logFunnelStep(player, funnelName, sessionId, step, stepName);
	},

	runStep(player: Player, runId: string, step: number, stepName: string): void {
		logFunnelStep(player, "CoreRun", runId, step, stepName);
	},

	// ── Onboarding funnel (first-session players only, each step once) ───────────
	onboardingStep(player: Player, step: number, stepName: string): void {
		if (!PlayerProgressionService.isFirstSession(player)) return;
		let sent = onboardingSent.get(player);
		if (!sent) {
			sent = new Set<number>();
			onboardingSent.set(player, sent);
		}
		if (sent.has(step)) return;
		sent.add(step);
		pcall(() => RobloxAnalytics.LogOnboardingFunnelStepEvent(player, step, stepName));
	},

	// ── Economy ─────────────────────────────────────────────────────────────────
	cashSource(player: Player, amount: number, endingBalance: number, transactionType: string, itemSku?: string): void {
		if (amount <= 0) return;
		pcall(() =>
			RobloxAnalytics.LogEconomyEvent(
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				CURRENCY,
				amount,
				endingBalance,
				transactionType,
				itemSku,
			),
		);
	},

	cashSink(player: Player, amount: number, endingBalance: number, transactionType: string, itemSku?: string): void {
		if (amount <= 0) return;
		pcall(() =>
			RobloxAnalytics.LogEconomyEvent(
				player,
				Enum.AnalyticsEconomyFlowType.Sink,
				CURRENCY,
				amount,
				endingBalance,
				transactionType,
				itemSku,
			),
		);
	},

	// ── Progression (rebirth milestones) ────────────────────────────────────────
	rebirth(player: Player, rebirths: number): void {
		pcall(() =>
			RobloxAnalytics.LogProgressionEvent(
				player,
				"Rebirth",
				Enum.AnalyticsProgressionType.Complete,
				rebirths,
				`Rebirth ${rebirths}`,
			),
		);
	},

	// ── Custom counters (optional numeric value + up to 3 breakdown fields) ─────
	// The dashboard counts the events on its own, so `value` is the magnitude of the
	// fact (reward, seconds, multiplier) and the fields are the dimensions to slice by.
	custom(
		player: Player,
		eventName: string,
		value?: number,
		field?: string | number,
		field2?: string | number,
		field3?: string | number,
	): void {
		pcall(() => RobloxAnalytics.LogCustomEvent(player, eventName, value, buildFields(field, field2, field3)));
	},
};
