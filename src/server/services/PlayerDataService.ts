import { DataStoreService, Players } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT } from "server/modules/CheatConfig";

// Per-player data persisted via DataStoreService. Mirrored to Roblox attributes
// so the owning client can read state directly (auto-replication).
//
// Stores:
//   • Numeric values listed in NUMERIC_KEYS → mirrored as same-name attributes
//     (Money → player.GetAttribute("Money")).
//   • Per-button unlock booleans keyed by a button's "DataName" attribute →
//     mirrored as Unlocked_<dataName> attributes. New players have an empty
//     map (= every button locked).
//
// NB: DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

const NUMERIC_KEYS = ["Money"] as const;
export type NumericKey = (typeof NUMERIC_KEYS)[number];

type PlayerData = {
	[K in NumericKey]: number;
} & {
	UnlockedButtons: { [dataName: string]: boolean };
};

const DEFAULT_DATA: PlayerData = {
	Money: 0,
	UnlockedButtons: {},
};

// Bump the store name (e.g. "_v2") if you ever need to reset everyone's data.
const STORE_NAME = "PlayerData_v1";
const dataStore = DataStoreService.GetDataStore(STORE_NAME);

// Only players whose data loaded successfully are eligible for save — avoids
// wiping a player's progress because of a transient DataStore failure.
const loadedPlayers = new Set<Player>();

// Per-player in-memory cache of the unlock map. Source of truth on the server;
// mirrored to attributes for client visibility, saved to DataStore on leave.
const unlocksCache = new Map<Player, { [dataName: string]: boolean }>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function unlockAttrName(dataName: string): string {
	return `Unlocked_${dataName}`;
}

function loadData(player: Player): PlayerData | undefined {
	// CHEAT — skip the load entirely, hand back a default profile. The next
	// regular save (PlayerRemoving / BindToClose) will overwrite the stored
	// entry with whatever fresh state the player ends up with.
	if (RESET_DATA_CHEAT) {
		warn(`PlayerDataService: resetData cheat — wiping in-memory state for ${player.Name}`);
		return { ...DEFAULT_DATA, UnlockedButtons: {} };
	}

	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`PlayerDataService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined) return { ...DEFAULT_DATA, UnlockedButtons: {} };
	if (!typeIs(result, "table")) return { ...DEFAULT_DATA, UnlockedButtons: {} };

	const loaded = result as Partial<PlayerData>;
	const merged: PlayerData = { ...DEFAULT_DATA, UnlockedButtons: {} };

	for (const key of NUMERIC_KEYS) {
		const value = loaded[key];
		if (typeIs(value, "number")) merged[key] = value;
	}

	if (typeIs(loaded.UnlockedButtons, "table")) {
		const raw = loaded.UnlockedButtons as { [k: string]: unknown };
		for (const [k, v] of pairs(raw)) {
			if (typeIs(k, "string") && v === true) merged.UnlockedButtons[k] = true;
		}
	}

	return merged;
}

function setupPlayer(player: Player): void {
	const data = loadData(player);
	const apply = data ?? { ...DEFAULT_DATA, UnlockedButtons: {} };

	for (const key of NUMERIC_KEYS) {
		player.SetAttribute(key, apply[key]);
	}

	// Replicate unlocks via attributes and keep a server cache for save+lookup
	const cache: { [dataName: string]: boolean } = {};
	for (const [dataName, isUnlocked] of pairs(apply.UnlockedButtons)) {
		if (typeIs(dataName, "string") && isUnlocked === true) {
			cache[dataName] = true;
			player.SetAttribute(unlockAttrName(dataName), true);
		}
	}
	unlocksCache.set(player, cache);

	if (data !== undefined) loadedPlayers.add(player);
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;

	const data: PlayerData = { ...DEFAULT_DATA, UnlockedButtons: {} };
	for (const key of NUMERIC_KEYS) {
		data[key] = (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
	}
	const cached = unlocksCache.get(player) ?? {};
	for (const [k, v] of pairs(cached)) {
		if (typeIs(k, "string") && v === true) data.UnlockedButtons[k] = true;
	}

	const [success, err] = pcall(() => dataStore.SetAsync(keyFor(player), data));
	if (!success) warn(`PlayerDataService: failed to save ${player.Name}: ${err}`);
}

export const PlayerDataService = {
	init(): void {
		Players.PlayerAdded.Connect(setupPlayer);
		for (const player of Players.GetPlayers()) setupPlayer(player);

		Players.PlayerRemoving.Connect((player) => {
			savePlayer(player);
			loadedPlayers.delete(player);
			unlocksCache.delete(player);
		});

		// Roblox waits up to 30s on BindToClose — save everyone in parallel so a
		// slow save doesn't starve the others before the deadline.
		game.BindToClose(() => {
			const players = Players.GetPlayers();
			if (players.size() === 0) return;
			let remaining = players.size();
			for (const player of players) {
				task.spawn(() => {
					savePlayer(player);
					remaining -= 1;
				});
			}
			while (remaining > 0) task.wait(0.1);
		});
	},

	// ── Numeric API ───────────────────────────────────────────────────────────
	get(player: Player, key: NumericKey): number {
		return (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
	},

	set(player: Player, key: NumericKey, value: number): void {
		player.SetAttribute(key, value);
	},

	add(player: Player, key: NumericKey, amount: number): void {
		this.set(player, key, this.get(player, key) + amount);
	},

	// ── Button unlocks ────────────────────────────────────────────────────────
	isButtonUnlocked(player: Player, dataName: string): boolean {
		return unlocksCache.get(player)?.[dataName] === true;
	},

	setButtonUnlocked(player: Player, dataName: string): void {
		let cache = unlocksCache.get(player);
		if (!cache) {
			cache = {};
			unlocksCache.set(player, cache);
		}
		cache[dataName] = true;
		player.SetAttribute(unlockAttrName(dataName), true);
	},
};
