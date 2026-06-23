-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local Players = _services.Players
local Workspace = _services.Workspace
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local renderBoard = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "LeaderboardBoard").renderBoard
local renderPodium = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "PodiumDisplay").renderPodium
local _NumberFormat = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat")
local FormatCash = _NumberFormat.FormatCash
local formatDuration = _NumberFormat.formatDuration
local Cfg = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "LeaderboardConfig")
-- Global persistent leaderboards (money + total playtime) and the top-3 money
-- podium. Server-authoritative: a self-driven loop flushes each player's score
-- to two OrderedDataStores, reads the top N, and renders the world boards + rigs.
-- Everything replicates — no RemoteEvent, no client script.
local moneyStore = DataStoreService:GetOrderedDataStore(Cfg.MONEY_STORE)
local playtimeStore = DataStoreService:GetOrderedDataStore(Cfg.PLAYTIME_STORE)
-- os.time() of the last playtime flush, per player (wall-clock seconds).
local lastFlush = {}
-- userId → display name, resolved once (names rarely change within a session).
local nameCache = {}
local function resolveName(userId)
	local _userId = userId
	local cached = nameCache[_userId]
	if cached ~= nil then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok then name else `User{userId}`
	local _userId_1 = userId
	nameCache[_userId_1] = resolved
	return resolved
end
-- Accumulate elapsed seconds into Playtime, then mirror Money + Playtime to the
-- ordered stores. Yields (WRITE_SPACING) to spread DataStore traffic.
local function flushPlayer(player)
	local now = os.time()
	local _player = player
	local _condition = lastFlush[_player]
	if _condition == nil then
		_condition = now
	end
	local last = _condition
	local delta = now - last
	if delta > 0 then
		PlayerDataService:add(player, "Playtime", delta)
		local _player_1 = player
		lastFlush[_player_1] = now
	end
	local key = tostring(player.UserId)
	local money = math.max(0, math.floor(PlayerDataService:get(player, "Money")))
	local playtime = math.max(0, math.floor(PlayerDataService:get(player, "Playtime")))
	pcall(function()
		return moneyStore:SetAsync(key, money)
	end)
	task.wait(Cfg.WRITE_SPACING)
	pcall(function()
		return playtimeStore:SetAsync(key, playtime)
	end)
	task.wait(Cfg.WRITE_SPACING)
end
local function readTop(store)
	local entries = {}
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Cfg.TOP_N)
	end)
	if not ok then
		return entries
	end
	local page = pages:GetCurrentPage()
	for _, item in page do
		local userId = tonumber(item.key)
		if userId == nil then
			continue
		end
		local _arg0 = {
			userId = userId,
			name = resolveName(userId),
			value = item.value,
		}
		table.insert(entries, _arg0)
	end
	return entries
end
local function leaderboardsFolder()
	local env = Workspace:FindFirstChild("Environment")
	local _result = env
	if _result ~= nil then
		_result = _result:FindFirstChild(Cfg.LEADERBOARDS_FOLDER)
	end
	return _result
end
local function refresh()
	for _, player in Players:GetPlayers() do
		flushPlayer(player)
	end
	local moneyTop = readTop(moneyStore)
	local playtimeTop = readTop(playtimeStore)
	local folder = leaderboardsFolder()
	if not folder then
		return nil
	end
	local moneyBoard = folder:FindFirstChild(Cfg.MONEY_BOARD)
	if moneyBoard then
		renderBoard(moneyBoard, moneyTop, FormatCash)
	end
	local playtimeBoard = folder:FindFirstChild(Cfg.PLAYTIME_BOARD)
	if playtimeBoard then
		renderBoard(playtimeBoard, playtimeTop, formatDuration)
	end
	local podium = folder:FindFirstChild(Cfg.PODIUM_FOLDER)
	if podium then
		local top3 = {}
		for i = 0, 2 do
			local entry = moneyTop[i + 1]
			if entry then
				table.insert(top3, entry)
			end
		end
		renderPodium(podium, top3, FormatCash)
	end
end
local LeaderboardService = {
	init = function(self)
		Players.PlayerAdded:Connect(function(player)
			local _player = player
			local _arg1 = os.time()
			lastFlush[_player] = _arg1
			return lastFlush
		end)
		for _, player in Players:GetPlayers() do
			local _arg1 = os.time()
			lastFlush[player] = _arg1
		end
		Players.PlayerRemoving:Connect(function(player)
			flushPlayer(player)
			local _player = player
			lastFlush[_player] = nil
		end)
		task.spawn(function()
			while true do
				local ok, err = pcall(refresh)
				if not ok then
					warn(`LeaderboardService refresh failed: {err}`)
				end
				task.wait(Cfg.REFRESH_INTERVAL)
			end
		end)
	end,
}
return {
	LeaderboardService = LeaderboardService,
}
