import { DataStoreService, Players } from "@rbxts/services";
import { resetData as RESET_DATA_CHEAT } from "server/modules/CheatConfig";
import { ShopStat, STATS, rebirthMult, moneyMult, effectiveSafety } from "shared/ShopConfig";

// Per-player progression. The LEVELS are the persisted source of truth; the
// effective values (BaseCash, RocketSpeed, AdditionalSecurity) are *derived* from
// the levels via shared/ShopConfig and mirrored to attributes so the owning
// client, the game loop and the room billboard read them directly (replication).
//
// Stored per player (DataStore): BaseCashLevel, RocketSpeedLevel, SafetyLevel.
// Mirrored attributes: the three level attributes AND the three value attributes.
//
// DataStore access requires API Services enabled in Studio:
// Game Settings → Security → "Enable Studio Access to API Services".

// The three stats, in a stable iteration order.
const STAT_LIST: readonly ShopStat[] = ["BaseCash", "RocketSpeed", "Safety"];

// Persisted alongside the stat levels (same store table). The reward multiplier
// is derived from it like the stat values are derived from their levels.
const REBIRTHS_KEY = "Rebirths";
const MULT_REBIRTH_ATTR = "MultRebirth";

// Boost input attributes (written by BoostService; defaulted here so deriveValues
// is safe before BoostService resolves). game.ts reads the derived attrs below.
const IN_COMMUNITY_ATTR = "InCommunity";
const MONEY_TIER_MULT_ATTR = "MoneyTierMult";
const HAS_SAFETY_PASS_ATTR = "HasSafetyPass";
// Derived, replicated for the game loop / billboard / shop readout.
const MONEY_MULT_ATTR = "MoneyMult";
const EFFECTIVE_BASE_CASH_ATTR = "EffectiveBaseCash";

// Value attributes the rest of the game reads (names unchanged from before).
export type ProgressionKey = "BaseCash" | "RocketSpeed" | "AdditionalSecurity" | "EffectiveBaseCash" | "MoneyMult";

// Fallback values if a value attribute is somehow missing (matches level 0).
const DEFAULT_VALUES: { readonly [K in ProgressionKey]: number } = {
	BaseCash: 100,
	RocketSpeed: 1,
	AdditionalSecurity: 0,
	EffectiveBaseCash: 100,
	MoneyMult: 1,
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
	levels[REBIRTHS_KEY] = 0;
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
	const rebirths = levels[REBIRTHS_KEY] ?? 0;
	player.SetAttribute(REBIRTHS_KEY, rebirths);
	player.SetAttribute(MULT_REBIRTH_ATTR, rebirthMult(rebirths));
	deriveValues(player);
}

// Folds the boost inputs into the replicated derived values. Additive money
// multiplier (shared/ShopConfig.moneyMult) → EffectiveBaseCash; safety pass →
// AdditionalSecurity. Reads level/rebirth/input attributes already set on the
// player. Called after every state change (load, purchase, rebirth, boost
// resolve) so the billboard / game loop / shop read one source of truth.
function deriveValues(player: Player): void {
	const baseCashLevel = (player.GetAttribute(STATS.BaseCash.levelAttribute) as number | undefined) ?? 0;
	const rawBase = STATS.BaseCash.valueFor(baseCashLevel);
	const multRebirth = (player.GetAttribute(MULT_REBIRTH_ATTR) as number | undefined) ?? rebirthMult(0);
	const tierMult = (player.GetAttribute(MONEY_TIER_MULT_ATTR) as number | undefined) ?? 1;
	const inCommunity = player.GetAttribute(IN_COMMUNITY_ATTR) === true;

	const mMult = moneyMult(multRebirth, tierMult, inCommunity);
	player.SetAttribute(MONEY_MULT_ATTR, mMult);
	player.SetAttribute(EFFECTIVE_BASE_CASH_ATTR, math.floor(rawBase * mMult));

	const safetyLevel = (player.GetAttribute(STATS.Safety.levelAttribute) as number | undefined) ?? 0;
	const rawSafety = STATS.Safety.valueFor(safetyLevel);
	const hasPass = player.GetAttribute(HAS_SAFETY_PASS_ATTR) === true;
	player.SetAttribute(STATS.Safety.valueAttribute, effectiveSafety(rawSafety, hasPass));
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
	const rebirthsLoaded = loaded[REBIRTHS_KEY];
	if (typeIs(rebirthsLoaded, "number")) merged[REBIRTHS_KEY] = math.max(0, math.floor(rebirthsLoaded));
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
	data[REBIRTHS_KEY] = (player.GetAttribute(REBIRTHS_KEY) as number | undefined) ?? 0;

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

	// Reads a derived value (BaseCash / RocketSpeed / AdditionalSecurity / EffectiveBaseCash / MoneyMult).
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
		deriveValues(player);
	},

	// Reads the persisted rebirth count.
	getRebirths(player: Player): number {
		return (player.GetAttribute(REBIRTHS_KEY) as number | undefined) ?? 0;
	},

	// Reads the derived permanent money multiplier.
	getMultRebirth(player: Player): number {
		return (player.GetAttribute(MULT_REBIRTH_ATTR) as number | undefined) ?? rebirthMult(0);
	},

	// Performs a rebirth: resets the 3 stat levels to 0 and increments Rebirths,
	// re-deriving every value. Does NOT touch Money — the caller resets that.
	rebirth(player: Player): void {
		for (const stat of STAT_LIST) {
			const cfg = STATS[stat];
			player.SetAttribute(cfg.levelAttribute, 0);
			player.SetAttribute(cfg.valueAttribute, cfg.valueFor(0));
		}
		const nextRebirths = this.getRebirths(player) + 1;
		player.SetAttribute(REBIRTHS_KEY, nextRebirths);
		player.SetAttribute(MULT_REBIRTH_ATTR, rebirthMult(nextRebirths));
		deriveValues(player);
	},

	// Re-derives MoneyMult / EffectiveBaseCash / AdditionalSecurity from the
	// current level + rebirth + boost-input attributes. Called by BoostService
	// after it writes the input attributes (group / game-pass ownership).
	recompute(player: Player): void {
		deriveValues(player);
	},
};
