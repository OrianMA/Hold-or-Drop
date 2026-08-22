-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local Players = _services.Players
local RESET_DATA_CHEAT = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").resetData
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local STATS = _ShopConfig.STATS
local rebirthMult = _ShopConfig.rebirthMult
local moneyMult = _ShopConfig.moneyMult
local effectiveResistance = _ShopConfig.effectiveResistance
local SCROLL_MONEY_BOOST = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig").SCROLL_MONEY_BOOST
-- Per-player progression. The LEVELS are the persisted source of truth; the
-- effective values (BaseCash, RocketSpeed, Resistance) are *derived* from
-- the levels via shared/ShopConfig and mirrored to attributes so the owning
-- client, the game loop and the room billboard read them directly (replication).
--
-- Stored per player (DataStore): BaseCashLevel, RocketSpeedLevel, ResistanceLevel.
-- Mirrored attributes: the three level attributes AND the three value attributes.
--
-- DataStore access requires API Services enabled in Studio:
-- Game Settings → Security → "Enable Studio Access to API Services".
-- The three stats, in a stable iteration order.
local STAT_LIST = { "BaseCash", "RocketSpeed", "Resistance" }
-- Persisted alongside the stat levels (same store table). The reward multiplier
-- is derived from it like the stat values are derived from their levels.
local REBIRTHS_KEY = "Rebirths"
local MULT_REBIRTH_ATTR = "MultRebirth"
-- Boost input attributes (written by BoostService; defaulted here so deriveValues
-- is safe before BoostService resolves). game.ts reads the derived attrs below.
local IN_COMMUNITY_ATTR = "InCommunity"
local MONEY_TIER_MULT_ATTR = "MoneyTierMult"
local HAS_RESISTANCE_PASS_ATTR = "HasResistancePass"
-- Derived, replicated for the game loop / billboard / shop readout.
local MONEY_MULT_ATTR = "MoneyMult"
local EFFECTIVE_BASE_CASH_ATTR = "EffectiveBaseCash"
-- Value attributes the rest of the game reads.
-- Fallback values if a value attribute is somehow missing (matches level 0).
local DEFAULT_VALUES = {
	BaseCash = 100,
	RocketSpeed = 1,
	Resistance = 0,
	EffectiveBaseCash = 100,
	MoneyMult = 1,
}
-- Schema changed from values → levels, so the store name is bumped to _v2.
local STORE_NAME = "PlayerProgression_v2"
local dataStore = DataStoreService:GetDataStore(STORE_NAME)
-- Only players whose data loaded successfully are eligible for save — avoids
-- wiping a player's progress because of a transient DataStore failure.
local loadedPlayers = {}
-- Players whose DataStore load returned NO existing record — i.e. their very first
-- session ever. Used to gate the onboarding analytics funnel (AnalyticsService) so it
-- only measures genuinely new players. Session-only; not persisted.
local firstSessionPlayers = {}
local function keyFor(player)
	return `Player_{player.UserId}`
end
local function defaultLevels()
	local levels = {}
	for _, stat in STAT_LIST do
		levels[STATS[stat].levelAttribute] = 0
	end
	levels[REBIRTHS_KEY] = 0
	return levels
end
-- Sets both the level attribute and the derived value attribute for every stat.
local deriveValues
local function applyLevels(player, levels)
	for _, stat in STAT_LIST do
		local cfg = STATS[stat]
		local _condition = levels[cfg.levelAttribute]
		if _condition == nil then
			_condition = 0
		end
		local level = _condition
		player:SetAttribute(cfg.levelAttribute, level)
		player:SetAttribute(cfg.valueAttribute, cfg.valueFor(level))
	end
	local _condition = levels[REBIRTHS_KEY]
	if _condition == nil then
		_condition = 0
	end
	local rebirths = _condition
	player:SetAttribute(REBIRTHS_KEY, rebirths)
	player:SetAttribute(MULT_REBIRTH_ATTR, rebirthMult(rebirths))
	deriveValues(player)
end
-- Folds the boost inputs into the replicated derived values. Additive money
-- multiplier (shared/ShopConfig.moneyMult) → EffectiveBaseCash; resistance pass →
-- Resistance. Reads level/rebirth/input attributes already set on the
-- player. Called after every state change (load, purchase, rebirth, boost
-- resolve) so the billboard / game loop / shop read one source of truth.
function deriveValues(player)
	local _condition = (player:GetAttribute(STATS.BaseCash.levelAttribute))
	if _condition == nil then
		_condition = 0
	end
	local baseCashLevel = _condition
	local rawBase = STATS.BaseCash.valueFor(baseCashLevel)
	local _condition_1 = (player:GetAttribute(MULT_REBIRTH_ATTR))
	if _condition_1 == nil then
		_condition_1 = rebirthMult(0)
	end
	local multRebirth = _condition_1
	local _condition_2 = (player:GetAttribute(MONEY_TIER_MULT_ATTR))
	if _condition_2 == nil then
		_condition_2 = 1
	end
	local tierMult = _condition_2
	local inCommunity = player:GetAttribute(IN_COMMUNITY_ATTR) == true
	-- Boost ×1.25 acheté en ScrollToken : persisté par PlayerDataService (0/1), donc
	-- déjà posé en attribut quand on arrive ici (PlayerData init AVANT Progression).
	local _condition_3 = (player:GetAttribute(SCROLL_MONEY_BOOST.attribute))
	if _condition_3 == nil then
		_condition_3 = 0
	end
	local hasScrollBoost = _condition_3 > 0
	local mMult = moneyMult(multRebirth, tierMult, inCommunity, hasScrollBoost)
	player:SetAttribute(MONEY_MULT_ATTR, mMult)
	player:SetAttribute(EFFECTIVE_BASE_CASH_ATTR, math.floor(rawBase * mMult))
	local _condition_4 = (player:GetAttribute(STATS.Resistance.levelAttribute))
	if _condition_4 == nil then
		_condition_4 = 0
	end
	local resistanceLevel = _condition_4
	local rawResistance = STATS.Resistance.valueFor(resistanceLevel)
	local hasPass = player:GetAttribute(HAS_RESISTANCE_PASS_ATTR) == true
	player:SetAttribute(STATS.Resistance.valueAttribute, effectiveResistance(rawResistance, hasPass))
end
local function loadLevels(player)
	if RESET_DATA_CHEAT then
		warn(`PlayerProgressionService: resetData cheat — wiping in-memory state for {player.Name}`)
		return defaultLevels()
	end
	local success, result = pcall(function()
		return dataStore:GetAsync(keyFor(player))
	end)
	if not success then
		warn(`PlayerProgressionService: failed to load {player.Name}: {result}`)
		return nil
	end
	-- No stored record → this is the player's first-ever session (onboarding funnel gate).
	if result == nil then
		local _player = player
		firstSessionPlayers[_player] = true
		return defaultLevels()
	end
	if not (type(result) == "table") then
		return defaultLevels()
	end
	local loaded = result
	local merged = defaultLevels()
	for _, stat in STAT_LIST do
		local key = STATS[stat].levelAttribute
		local value = loaded[key]
		if type(value) == "number" then
			merged[key] = math.max(0, math.floor(value))
		end
	end
	local rebirthsLoaded = loaded[REBIRTHS_KEY]
	if type(rebirthsLoaded) == "number" then
		merged[REBIRTHS_KEY] = math.max(0, math.floor(rebirthsLoaded))
	end
	return merged
end
local function setupPlayer(player)
	local levels = loadLevels(player)
	applyLevels(player, levels or defaultLevels())
	if levels ~= nil then
		local _player = player
		loadedPlayers[_player] = true
	end
end
local function savePlayer(player)
	local _player = player
	if not (loadedPlayers[_player] ~= nil) then
		return nil
	end
	local data = defaultLevels()
	for _, stat in STAT_LIST do
		local key = STATS[stat].levelAttribute
		local _condition = (player:GetAttribute(key))
		if _condition == nil then
			_condition = 0
		end
		data[key] = _condition
	end
	local _condition = (player:GetAttribute(REBIRTHS_KEY))
	if _condition == nil then
		_condition = 0
	end
	data[REBIRTHS_KEY] = _condition
	local success, err = pcall(function()
		return dataStore:SetAsync(keyFor(player), data)
	end)
	if not success then
		warn(`PlayerProgressionService: failed to save {player.Name}: {err}`)
	end
end
local PlayerProgressionService = {
	init = function(self)
		Players.PlayerAdded:Connect(setupPlayer)
		for _, player in Players:GetPlayers() do
			setupPlayer(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			savePlayer(player)
			local _player = player
			loadedPlayers[_player] = nil
			local _player_1 = player
			firstSessionPlayers[_player_1] = nil
		end)
		-- Roblox waits up to 30s on BindToClose — save everyone in parallel so a
		-- slow save doesn't starve the others before the deadline.
		game:BindToClose(function()
			local players = Players:GetPlayers()
			if #players == 0 then
				return nil
			end
			local remaining = #players
			for _, player in players do
				task.spawn(function()
					savePlayer(player)
					remaining -= 1
				end)
			end
			while remaining > 0 do
				task.wait(0.1)
			end
		end)
	end,
	get = function(self, player, key)
		local _condition = (player:GetAttribute(key))
		if _condition == nil then
			_condition = DEFAULT_VALUES[key]
		end
		return _condition
	end,
	getLevel = function(self, player, stat)
		local _condition = (player:GetAttribute(STATS[stat].levelAttribute))
		if _condition == nil then
			_condition = 0
		end
		return _condition
	end,
	addLevel = function(self, player, stat, amount)
		local cfg = STATS[stat]
		local nextLevel = self:getLevel(player, stat) + amount
		if cfg.maxLevel ~= nil then
			nextLevel = math.min(nextLevel, cfg.maxLevel)
		end
		nextLevel = math.max(0, math.floor(nextLevel))
		player:SetAttribute(cfg.levelAttribute, nextLevel)
		player:SetAttribute(cfg.valueAttribute, cfg.valueFor(nextLevel))
		deriveValues(player)
	end,
	isFirstSession = function(self, player)
		local _player = player
		return firstSessionPlayers[_player] ~= nil
	end,
	getRebirths = function(self, player)
		local _condition = (player:GetAttribute(REBIRTHS_KEY))
		if _condition == nil then
			_condition = 0
		end
		return _condition
	end,
	getMultRebirth = function(self, player)
		local _condition = (player:GetAttribute(MULT_REBIRTH_ATTR))
		if _condition == nil then
			_condition = rebirthMult(0)
		end
		return _condition
	end,
	rebirth = function(self, player)
		for _, stat in STAT_LIST do
			local cfg = STATS[stat]
			player:SetAttribute(cfg.levelAttribute, 0)
			player:SetAttribute(cfg.valueAttribute, cfg.valueFor(0))
		end
		local nextRebirths = self:getRebirths(player) + 1
		player:SetAttribute(REBIRTHS_KEY, nextRebirths)
		player:SetAttribute(MULT_REBIRTH_ATTR, rebirthMult(nextRebirths))
		deriveValues(player)
	end,
	safeRebirth = function(self, player)
		local nextRebirths = self:getRebirths(player) + 1
		player:SetAttribute(REBIRTHS_KEY, nextRebirths)
		player:SetAttribute(MULT_REBIRTH_ATTR, rebirthMult(nextRebirths))
		deriveValues(player)
	end,
	recompute = function(self, player)
		deriveValues(player)
	end,
}
return {
	PlayerProgressionService = PlayerProgressionService,
}
