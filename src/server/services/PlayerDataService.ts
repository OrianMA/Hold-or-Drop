import { DataStoreService, Players } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT } from "server/modules/CheatConfig";

// Per-player data persisted via DataStoreService. Mirrored to Roblox attributes
// so the owning client can read state directly (auto-replication).
//
// Stores numeric values listed in NUMERIC_KEYS → mirrored as same-name
// attributes (Money → player.GetAttribute("Money")).
//
// NB: DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

const NUMERIC_KEYS = ["Money", "Playtime", "DailyStreak", "DailyLastClaim"] as const;
export type NumericKey = (typeof NUMERIC_KEYS)[number];

type PlayerData = {
	[K in NumericKey]: number;
};

const DEFAULT_DATA: PlayerData = {
	Money: 0,
	Playtime: 0, // total seconds played, accumulated across sessions
	DailyStreak: 0, // consecutive days claimed (see DailyRewardService)
	DailyLastClaim: 0, // UTC day index of the last claim, 0 = never claimed
};

// Bump the store name (e.g. "_v2") if you ever need to reset everyone's data.
const STORE_NAME = "PlayerData_v1";
const dataStore = DataStoreService.GetDataStore(STORE_NAME);

// Only players whose data loaded successfully are eligible for save — avoids
// wiping a player's progress because of a transient DataStore failure.
const loadedPlayers = new Set<Player>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function loadData(player: Player): PlayerData | undefined {
	// CHEAT — skip the load entirely, hand back a default profile. The next
	// regular save (PlayerRemoving / BindToClose) will overwrite the stored
	// entry with whatever fresh state the player ends up with.
	if (RESET_DATA_CHEAT) {
		warn(`PlayerDataService: resetData cheat — wiping in-memory state for ${player.Name}`);
		return { ...DEFAULT_DATA };
	}

	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`PlayerDataService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined) return { ...DEFAULT_DATA };
	if (!typeIs(result, "table")) return { ...DEFAULT_DATA };

	const loaded = result as Partial<PlayerData>;
	const merged: PlayerData = { ...DEFAULT_DATA };
	for (const key of NUMERIC_KEYS) {
		const value = loaded[key];
		if (typeIs(value, "number")) merged[key] = value;
	}
	return merged;
}

function setupPlayer(player: Player): void {
	const data = loadData(player);
	const apply = data ?? { ...DEFAULT_DATA };

	for (const key of NUMERIC_KEYS) {
		player.SetAttribute(key, apply[key]);
	}

	if (data !== undefined) loadedPlayers.add(player);
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;

	const data: PlayerData = { ...DEFAULT_DATA };
	for (const key of NUMERIC_KEYS) {
		data[key] = (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
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

	get(player: Player, key: NumericKey): number {
		return (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
	},

	set(player: Player, key: NumericKey, value: number): void {
		player.SetAttribute(key, value);
	},

	add(player: Player, key: NumericKey, amount: number): void {
		this.set(player, key, this.get(player, key) + amount);
	},
};
