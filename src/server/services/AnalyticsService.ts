import { AnalyticsService as RobloxAnalytics, HttpService, Players } from "@rbxts/services";
import { PlayerProgressionService } from "./PlayerProgressionService";

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
//   Custom   → per-event counters with a breakdown field (RocketLaunched, RunLost, …).

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

export const AnalyticsService = {
	init(): void {
		const onJoin = (player: Player): void => {
			task.spawn(() => {
				// Wait until progression finished loading (it sets Rebirths at the end of
				// the async load), so isFirstSession is decided before the join step.
				if (player.GetAttribute("Rebirths") === undefined) {
					player.GetAttributeChangedSignal("Rebirths").Wait();
				}
				AnalyticsService.onboardingStep(player, 1, "Joined");
			});
		};
		Players.PlayerAdded.Connect(onJoin);
		for (const player of Players.GetPlayers()) onJoin(player);

		Players.PlayerRemoving.Connect((player) => onboardingSent.delete(player));
	},

	// ── Run funnel (repeatable, one funnelSessionId per run) ────────────────────
	// A fresh, unique id for one run of the core loop (Launch → Claim → Banked).
	newRunId(): string {
		const [ok, id] = pcall(() => HttpService.GenerateGUID(false));
		return ok ? (id as string) : `${tick()}`;
	},

	runStep(player: Player, runId: string, step: number, stepName: string): void {
		pcall(() => RobloxAnalytics.LogFunnelStepEvent(player, "CoreRun", runId, step, stepName));
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

	// ── Custom counters (optional numeric value + one breakdown field) ──────────
	custom(player: Player, eventName: string, value?: number, field?: string | number): void {
		pcall(() => RobloxAnalytics.LogCustomEvent(player, eventName, value, buildFields(field)));
	},
};
