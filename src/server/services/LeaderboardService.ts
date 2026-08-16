import { DataStoreService, Players, Workspace } from "@rbxts/services";
import { PlayerDataService } from "./PlayerDataService";
import { renderBoard } from "server/modules/LeaderboardBoard";
import { renderPodium } from "server/modules/PodiumDisplay";
import { FormatCash, formatDuration } from "shared/NumberFormat";
import { RankedEntry } from "shared/LeaderboardConfig";
import * as Cfg from "shared/LeaderboardConfig";

// Global persistent leaderboards (money + total playtime) and the top-3 money
// podium. Server-authoritative: a self-driven loop flushes each player's score
// to two OrderedDataStores, reads the top N, and renders the world boards + rigs.
// Everything replicates — no RemoteEvent, no client script.

const moneyStore = DataStoreService.GetOrderedDataStore(Cfg.MONEY_STORE);
const playtimeStore = DataStoreService.GetOrderedDataStore(Cfg.PLAYTIME_STORE);

// os.time() of the last playtime flush, per player (wall-clock seconds).
const lastFlush = new Map<Player, number>();
// userId → display name, resolved once (names rarely change within a session).
const nameCache = new Map<number, string>();

// ── Money rank encoding ───────────────────────────────────────────────────────
// OrderedDataStore only accepts integers in the signed-64-bit range (max
// 9,223,372,036,854,775,807 ≈ "9.22Qi") — which is exactly where the money board
// used to freeze once a player crossed it. Instead of storing raw Money, we store
// a monotonic, order-preserving encoding: the base-10 exponent and mantissa packed
// into a small int. Sort order is identical to the real value's, decoding recovers
// ~15 significant digits (far more than the abbreviated display needs), and the
// effective ceiling rises to ~1e308 (double max).
const RANK_EXP_OFFSET = 40; // shifts small/negative exponents into positive range
const RANK_MANTISSA_SCALE = 1e15; // resolution of the [1, 10) mantissa

function encodeMoneyRank(value: number): number {
	if (value <= 0) return 0;
	let exp = math.floor(math.log(value, 10));
	let mantissa = value / 10 ** exp; // aim for [1, 10)
	if (mantissa >= 10) {
		mantissa /= 10;
		exp += 1;
	} else if (mantissa < 1) {
		mantissa *= 10;
		exp -= 1;
	}
	const mantissaPart = math.floor(((mantissa - 1) / 9) * RANK_MANTISSA_SCALE);
	return (exp + RANK_EXP_OFFSET) * RANK_MANTISSA_SCALE + mantissaPart;
}

function decodeMoneyRank(encoded: number): number {
	if (encoded <= 0) return 0;
	const expIndex = math.floor(encoded / RANK_MANTISSA_SCALE);
	const mantissaPart = encoded - expIndex * RANK_MANTISSA_SCALE;
	const exp = expIndex - RANK_EXP_OFFSET;
	const mantissa = 1 + (mantissaPart / RANK_MANTISSA_SCALE) * 9;
	return mantissa * 10 ** exp;
}

function resolveName(userId: number): string {
	const cached = nameCache.get(userId);
	if (cached !== undefined) return cached;
	const [ok, name] = pcall(() => Players.GetNameFromUserIdAsync(userId));
	const resolved = ok ? (name as string) : `User${userId}`;
	nameCache.set(userId, resolved);
	return resolved;
}

// Accumulate elapsed seconds into Playtime, then mirror Money + Playtime to the
// ordered stores. Yields (WRITE_SPACING) to spread DataStore traffic.
function flushPlayer(player: Player): void {
	const now = os.time();
	const last = lastFlush.get(player) ?? now;
	const delta = now - last;
	if (delta > 0) {
		PlayerDataService.add(player, "Playtime", delta);
		lastFlush.set(player, now);
	}
	const key = tostring(player.UserId);
	const money = math.max(0, math.floor(PlayerDataService.get(player, "Money")));
	const playtime = math.max(0, math.floor(PlayerDataService.get(player, "Playtime")));
	pcall(() => moneyStore.SetAsync(key, encodeMoneyRank(money)));
	task.wait(Cfg.WRITE_SPACING);
	pcall(() => playtimeStore.SetAsync(key, playtime));
	task.wait(Cfg.WRITE_SPACING);
}

// `decode` maps the stored integer back to the real value (identity for stores
// that keep raw values, decodeMoneyRank for the encoded money store).
function readTop(store: OrderedDataStore, decode: (v: number) => number = (v) => v): RankedEntry[] {
	const entries: RankedEntry[] = [];
	const [ok, pages] = pcall(() => store.GetSortedAsync(false, Cfg.TOP_N));
	if (!ok) return entries;
	const page = (pages as DataStorePages).GetCurrentPage();
	for (const item of page) {
		const userId = tonumber(item.key);
		if (userId === undefined) continue;
		entries.push({ userId, name: resolveName(userId), value: decode(item.value as number) });
	}
	return entries;
}

function leaderboardsFolder(): Instance | undefined {
	const env = Workspace.FindFirstChild("Environment");
	return env?.FindFirstChild(Cfg.LEADERBOARDS_FOLDER);
}

function refresh(): void {
	for (const player of Players.GetPlayers()) flushPlayer(player);

	const moneyTop = readTop(moneyStore, decodeMoneyRank);
	const playtimeTop = readTop(playtimeStore);

	const folder = leaderboardsFolder();
	if (!folder) return;

	const moneyBoard = folder.FindFirstChild(Cfg.MONEY_BOARD);
	if (moneyBoard) renderBoard(moneyBoard, moneyTop, FormatCash);

	const playtimeBoard = folder.FindFirstChild(Cfg.PLAYTIME_BOARD);
	if (playtimeBoard) renderBoard(playtimeBoard, playtimeTop, formatDuration);

	const podium = folder.FindFirstChild(Cfg.PODIUM_FOLDER);
	if (podium) {
		const top3: RankedEntry[] = [];
		for (let i = 0; i < 3; i++) {
			const entry = moneyTop[i];
			if (entry) top3.push(entry);
		}
		renderPodium(podium, top3, FormatCash);
	}
}

export const LeaderboardService = {
	init(): void {
		Players.PlayerAdded.Connect((player) => lastFlush.set(player, os.time()));
		for (const player of Players.GetPlayers()) lastFlush.set(player, os.time());

		Players.PlayerRemoving.Connect((player) => {
			flushPlayer(player); // bank the leaving player's score promptly
			lastFlush.delete(player);
		});

		task.spawn(() => {
			for (;;) {
				const [ok, err] = pcall(refresh);
				if (!ok) warn(`LeaderboardService refresh failed: ${err}`);
				task.wait(Cfg.REFRESH_INTERVAL);
			}
		});
	},
};
