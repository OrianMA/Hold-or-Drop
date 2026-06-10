import { DataStoreService, Players } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT } from "server/modules/CheatConfig";
import { ShopStat, STATS } from "shared/ShopConfig";

// Per-player progression. The LEVELS are the persisted source of truth; the
// effective values (BaseCash, Multiplier, AdditionalSecurity) are *derived* from
// the levels via shared/ShopConfig and mirrored to attributes so the owning
// client, the game loop and the room billboard read them directly (replication).
//
// Stored per player (DataStore): BaseCashLevel, MultiplierLevel, SafetyLevel.
// Mirrored attributes: the three level attributes AND the three value attributes.
//
// DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

// The three stats, in a stable iteration order.
const STAT_LIST: readonly ShopStat[] = ["BaseCash", "Multiplier", "Safety"];

// Value attributes the rest of the game reads (names unchanged from before).
export type ProgressionKey = "BaseCash" | "Multiplier" | "AdditionalSecurity";

// Fallback values if a value attribute is somehow missing (matches level 0).
const DEFAULT_VALUES: { readonly [K in ProgressionKey]: number } = {
	BaseCash: 100,
	Multiplier: 0.1,
	AdditionalSecurity: 0,
};

type LevelData = { [levelAttribute: string]: number };

// Schema changed from values → levels, so the store name is bumped to _v2.
const STORE_NAME = "PlayerProgression_v2";
const dataStore = DataStoreService.GetDataStore(STORE_NAME);

// Only players whose data loaded successfully are eligible for save — avoids
// wiping a player's progress because of a transient DataStore failure.
const loadedPlayers = new Set<Player>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function defaultLevels(): LevelData {
	const levels: LevelData = {};
	for (const stat of STAT_LIST) levels[STATS[stat].levelAttribute] = 0;
	return levels;
}

// Sets both the level attribute and the derived value attribute for every stat.
function applyLevels(player: Player, levels: LevelData): void {
	for (const stat of STAT_LIST) {
		const cfg = STATS[stat];
		const level = levels[cfg.levelAttribute] ?? 0;
		player.SetAttribute(cfg.levelAttribute, level);
		player.SetAttribute(cfg.valueAttribute, cfg.valueFor(level));
	}
}

function loadLevels(player: Player): LevelData | undefined {
	if (RESET_DATA_CHEAT) {
		warn(`PlayerProgressionService: resetData cheat — wiping in-memory state for ${player.Name}`);
		return defaultLevels();
	}

	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`PlayerProgressionService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined || !typeIs(result, "table")) return defaultLevels();

	const loaded = result as Partial<LevelData>;
	const merged = defaultLevels();
	for (const stat of STAT_LIST) {
		const key = STATS[stat].levelAttribute;
		const value = loaded[key];
		if (typeIs(value, "number")) merged[key] = math.max(0, math.floor(value));
	}
	return merged;
}

function setupPlayer(player: Player): void {
	const levels = loadLevels(player);
	applyLevels(player, levels ?? defaultLevels());
	if (levels !== undefined) loadedPlayers.add(player);
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;

	const data = defaultLevels();
	for (const stat of STAT_LIST) {
		const key = STATS[stat].levelAttribute;
		data[key] = (player.GetAttribute(key) as number | undefined) ?? 0;
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

	// Reads a derived value (BaseCash / Multiplier / AdditionalSecurity).
	get(player: Player, key: ProgressionKey): number {
		return (player.GetAttribute(key) as number | undefined) ?? DEFAULT_VALUES[key];
	},

	// Reads the persisted level of a stat.
	getLevel(player: Player, stat: ShopStat): number {
		return (player.GetAttribute(STATS[stat].levelAttribute) as number | undefined) ?? 0;
	},

	// Adds `amount` levels to a stat (clamped to its cap), re-deriving the value.
	// This is the only mutation path — the shop calls it after validating payment.
	addLevel(player: Player, stat: ShopStat, amount: number): void {
		const cfg = STATS[stat];
		let nextLevel = this.getLevel(player, stat) + amount;
		if (cfg.maxLevel !== undefined) nextLevel = math.min(nextLevel, cfg.maxLevel);
		nextLevel = math.max(0, math.floor(nextLevel));
		player.SetAttribute(cfg.levelAttribute, nextLevel);
		player.SetAttribute(cfg.valueAttribute, cfg.valueFor(nextLevel));
	},
};
