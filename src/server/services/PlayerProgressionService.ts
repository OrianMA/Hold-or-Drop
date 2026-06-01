import { DataStoreService, Players } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT } from "server/modules/CheatConfig";

// Per-player progression values persisted via DataStoreService and mirrored to
// Roblox attributes so the owning client can read state directly (auto-replication).
//
// Fields (all numeric — mirrored as same-name attributes):
//   • BaseCash           — base payout of the player's button
//   • Multiplier         — per-second multiplier that grows during gameplay
//   • AdditionalSecurity — clamped to [0, 1]; reduces the explosion risk
//
// DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

const NUMERIC_KEYS = ["BaseCash", "Multiplier", "AdditionalSecurity"] as const;
export type ProgressionKey = (typeof NUMERIC_KEYS)[number];

type ProgressionData = {
	[K in ProgressionKey]: number;
};

const DEFAULT_DATA: ProgressionData = {
	BaseCash: 100,
	Multiplier: 0.1,
	AdditionalSecurity: 0,
};

// Bump the store name (e.g. "_v2") if you ever need to reset everyone's progression.
const STORE_NAME = "PlayerProgression_v1";
const dataStore = DataStoreService.GetDataStore(STORE_NAME);

// Only players whose data loaded successfully are eligible for save — avoids
// wiping a player's progress because of a transient DataStore failure.
const loadedPlayers = new Set<Player>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function clampForKey(key: ProgressionKey, value: number): number {
	// AdditionalSecurity is a probability — outside [0, 1] would silently break gameplay math.
	if (key === "AdditionalSecurity") return math.clamp(value, 0, 1);
	return value;
}

function loadData(player: Player): ProgressionData | undefined {
	if (RESET_DATA_CHEAT) {
		warn(`PlayerProgressionService: resetData cheat — wiping in-memory state for ${player.Name}`);
		return { ...DEFAULT_DATA };
	}

	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`PlayerProgressionService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined) return { ...DEFAULT_DATA };
	if (!typeIs(result, "table")) return { ...DEFAULT_DATA };

	const loaded = result as Partial<ProgressionData>;
	const merged: ProgressionData = { ...DEFAULT_DATA };
	for (const key of NUMERIC_KEYS) {
		const value = loaded[key];
		if (typeIs(value, "number")) merged[key] = clampForKey(key, value);
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

	const data: ProgressionData = { ...DEFAULT_DATA };
	for (const key of NUMERIC_KEYS) {
		const value = (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
		data[key] = clampForKey(key, value);
	}

	const [success, err] = pcall(() => dataStore.SetAsync(keyFor(player), data));
	if (!success) warn(`PlayerProgressionService: failed to save ${player.Name}: ${err}`);
}

export const PlayerProgressionService = {
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

	get(player: Player, key: ProgressionKey): number {
		return (player.GetAttribute(key) as number | undefined) ?? DEFAULT_DATA[key];
	},

	set(player: Player, key: ProgressionKey, value: number): void {
		player.SetAttribute(key, clampForKey(key, value));
	},

	add(player: Player, key: ProgressionKey, amount: number): void {
		this.set(player, key, this.get(player, key) + amount);
	},
};
