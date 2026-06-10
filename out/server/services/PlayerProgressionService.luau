-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local Players = _services.Players
local RESET_DATA_CHEAT = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").resetData
local STATS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").STATS
-- Per-player progression. The LEVELS are the persisted source of truth; the
-- effective values (BaseCash, Multiplier, AdditionalSecurity) are *derived* from
-- the levels via shared/ShopConfig and mirrored to attributes so the owning
-- client, the game loop and the room billboard read them directly (replication).
--
-- Stored per player (DataStore): BaseCashLevel, MultiplierLevel, SafetyLevel.
-- Mirrored attributes: the three level attributes AND the three value attributes.
--
-- DataStore access requires API Services enabled in Studio:
-- Game Settings → Security → "Enable Studio Access to API Services".
-- The three stats, in a stable iteration order.
local STAT_LIST = { "BaseCash", "Multiplier", "Safety" }
-- Value attributes the rest of the game reads (names unchanged from before).
-- Fallback values if a value attribute is somehow missing (matches level 0).
local DEFAULT_VALUES = {
	BaseCash = 100,
	Multiplier = 0.1,
	AdditionalSecurity = 0,
}
-- Schema changed from values → levels, so the store name is bumped to _v2.
local STORE_NAME = "PlayerProgression_v2"
local dataStore = DataStoreService:GetDataStore(STORE_NAME)
-- Only players whose data loaded successfully are eligible for save — avoids
-- wiping a player's progress because of a transient DataStore failure.
local loadedPlayers = {}
local function keyFor(player)
	return `Player_{player.UserId}`
end
local function defaultLevels()
	local levels = {}
	for _, stat in STAT_LIST do
		levels[STATS[stat].levelAttribute] = 0
	end
	return levels
end
-- Sets both the level attribute and the derived value attribute for every stat.
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
	if result == nil or not (type(result) == "table") then
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
	end,
}
return {
	PlayerProgressionService = PlayerProgressionService,
}
