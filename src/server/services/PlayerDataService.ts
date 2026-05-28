import { DataStoreService, Players } from "@rbxts/services";

// Per-player numeric data persisted via DataStoreService. Loaded into Roblox
// attributes (which auto-replicate to the owning client) on join, saved back
// on PlayerRemoving and server shutdown. Add a new key to DATA_KEYS +
// DEFAULT_DATA to start tracking another currency / stat.
//
// NB: DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

const DATA_KEYS = ["Money"] as const;
export type DataKey = (typeof DATA_KEYS)[number];

type PlayerData = { [K in DataKey]: number };

const DEFAULT_DATA: PlayerData = { Money: 0 };

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
	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`PlayerDataService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined) return { ...DEFAULT_DATA };
	if (!typeIs(result, "table")) return { ...DEFAULT_DATA };

	const loaded = result as Partial<PlayerData>;
	const merged: PlayerData = { ...DEFAULT_DATA };
	for (const key of DATA_KEYS) {
		const value = loaded[key];
		if (typeIs(value, "number")) merged[key] = value;
	}
	return merged;
}

function setupPlayer(player: Player): void {
	const data = loadData(player);
	const apply = data ?? DEFAULT_DATA;
	for (const key of DATA_KEYS) {
		player.SetAttribute(key, apply[key]);
	}
	if (data !== undefined) loadedPlayers.add(player);
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;

	const data: PlayerData = { ...DEFAULT_DATA };
	for (const key of DATA_KEYS) {
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

	get(player: Player, key: DataKey): number {
		return (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
	},

	set(player: Player, key: DataKey, value: number): void {
		player.SetAttribute(key, value);
	},

	add(player: Player, key: DataKey, amount: number): void {
		this.set(player, key, this.get(player, key) + amount);
	},
};
