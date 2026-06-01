-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local Players = _services.Players
local RESET_DATA_CHEAT = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").resetData
-- Per-player progression values persisted via DataStoreService and mirrored to
-- Roblox attributes so the owning client can read state directly (auto-replication).
--
-- Fields (all numeric — mirrored as same-name attributes):
--   • BaseCash           — base payout of the player's button
--   • Multiplier         — per-second multiplier that grows during gameplay
--   • AdditionalSecurity — clamped to [0, 1]; reduces the explosion risk
--
-- DataStore access requires API Services enabled in Studio:
-- Game Settings → Security → "Enable Studio Access to API Services".
local NUMERIC_KEYS = { "BaseCash", "Multiplier", "AdditionalSecurity" }
local DEFAULT_DATA = {
	BaseCash = 100,
	Multiplier = 0.1,
	AdditionalSecurity = 0,
}
-- Bump the store name (e.g. "_v2") if you ever need to reset everyone's progression.
local STORE_NAME = "PlayerProgression_v1"
local dataStore = DataStoreService:GetDataStore(STORE_NAME)
-- Only players whose data loaded successfully are eligible for save — avoids
-- wiping a player's progress because of a transient DataStore failure.
local loadedPlayers = {}
local function keyFor(player)
	return `Player_{player.UserId}`
end
local function clampForKey(key, value)
	-- AdditionalSecurity is a probability — outside [0, 1] would silently break gameplay math.
	if key == "AdditionalSecurity" then
		return math.clamp(value, 0, 1)
	end
	return value
end
local function loadData(player)
	if RESET_DATA_CHEAT then
		warn(`PlayerProgressionService: resetData cheat — wiping in-memory state for {player.Name}`)
		local _object = table.clone(DEFAULT_DATA)
		setmetatable(_object, nil)
		return _object
	end
	local success, result = pcall(function()
		return dataStore:GetAsync(keyFor(player))
	end)
	if not success then
		warn(`PlayerProgressionService: failed to load {player.Name}: {result}`)
		return nil
	end
	if result == nil then
		local _object = table.clone(DEFAULT_DATA)
		setmetatable(_object, nil)
		return _object
	end
	if not (type(result) == "table") then
		local _object = table.clone(DEFAULT_DATA)
		setmetatable(_object, nil)
		return _object
	end
	local loaded = result
	local _object = table.clone(DEFAULT_DATA)
	setmetatable(_object, nil)
	local merged = _object
	for _, key in NUMERIC_KEYS do
		local value = loaded[key]
		if type(value) == "number" then
			merged[key] = clampForKey(key, value)
		end
	end
	return merged
end
local function setupPlayer(player)
	local data = loadData(player)
	local _condition = data
	if _condition == nil then
		local _object = table.clone(DEFAULT_DATA)
		setmetatable(_object, nil)
		_condition = _object
	end
	local apply = _condition
	for _, key in NUMERIC_KEYS do
		player:SetAttribute(key, apply[key])
	end
	if data ~= nil then
		local _player = player
		loadedPlayers[_player] = true
	end
end
local function savePlayer(player)
	local _player = player
	if not (loadedPlayers[_player] ~= nil) then
		return nil
	end
	local _object = table.clone(DEFAULT_DATA)
	setmetatable(_object, nil)
	local data = _object
	for _, key in NUMERIC_KEYS do
		local _condition = (player:GetAttribute(key))
		if _condition == nil then
			_condition = DEFAULT_DATA[key]
		end
		local value = _condition
		data[key] = clampForKey(key, value)
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
			_condition = DEFAULT_DATA[key]
		end
		return _condition
	end,
	set = function(self, player, key, value)
		player:SetAttribute(key, clampForKey(key, value))
	end,
	add = function(self, player, key, amount)
		self:set(player, key, self:get(player, key) + amount)
	end,
}
return {
	PlayerProgressionService = PlayerProgressionService,
}
