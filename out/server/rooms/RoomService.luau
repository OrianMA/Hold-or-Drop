-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local Room = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "Room").Room
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
-- Owns the player ↔ room mapping (the "player-only" domain).
--
-- At server start it scans Workspace/PlayerZones for P{n} folders (one Button
-- model each) and turns each into a Room. Players are assigned the first free
-- room in order on join and released on leave. The billboard of an occupied
-- room mirrors the occupant's BaseCash; empty rooms read "Empty".
--
-- The actual button gameplay (ButtonModule) consults getRooms()/owns() — this
-- service never touches the hold/risk loop.
local PLAYER_ZONES = "PlayerZones"
local rooms = {}
local roomByPlayer = {}
-- While a player is assigned, we mirror live BaseCash changes onto their room's
-- billboard (covers the DataStore load landing after the initial assign).
local baseCashConns = {}
-- "P2" → 2. Numeric-aware so P10 sorts after P9, not after P1.
local function roomOrder(name)
	local digits = string.match(name, "%d+")
	local _result
	if digits ~= nil then
		local _condition = tonumber(digits)
		if _condition == nil then
			_condition = 0
		end
		_result = _condition
	else
		_result = 0
	end
	return _result
end
local function assign(player)
	-- ▼ ReadonlyArray.find ▼
	local _callback = function(r)
		return r:isEmpty()
	end
	local _result
	for _i, _v in rooms do
		if _callback(_v, _i - 1, rooms) == true then
			_result = _v
			break
		end
	end
	-- ▲ ReadonlyArray.find ▲
	local room = _result
	if not room then
		warn(`RoomService: no free room for {player.Name} (all {#rooms} rooms occupied)`)
		return nil
	end
	room:assign(player)
	local _player = player
	roomByPlayer[_player] = room
	room:setGainCash(PlayerProgressionService:get(player, "BaseCash"))
	local conn = player:GetAttributeChangedSignal("BaseCash"):Connect(function()
		room:setGainCash(PlayerProgressionService:get(player, "BaseCash"))
	end)
	local _player_1 = player
	baseCashConns[_player_1] = conn
end
local function release(player)
	local _player = player
	local conn = baseCashConns[_player]
	if conn then
		conn:Disconnect()
		local _player_1 = player
		baseCashConns[_player_1] = nil
	end
	local _player_1 = player
	local room = roomByPlayer[_player_1]
	if not room then
		return nil
	end
	room:release()
	local _player_2 = player
	roomByPlayer[_player_2] = nil
end
local RoomService = {
	init = function(self)
		local zones = Workspace:WaitForChild(PLAYER_ZONES)
		local children = zones:GetChildren()
		table.sort(children, function(a, b)
			return roomOrder(a.Name) < roomOrder(b.Name)
		end)
		for _, child in children do
			local room = Room.new(child)
			if not room:isValid() then
				continue
			end
			room:release()
			table.insert(rooms, room)
		end
		Players.PlayerAdded:Connect(function(player)
			return assign(player)
		end)
		for _, player in Players:GetPlayers() do
			assign(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			return release(player)
		end)
	end,
	getRoom = function(self, player)
		local _player = player
		return roomByPlayer[_player]
	end,
	getRooms = function(self)
		return rooms
	end,
}
return {
	RoomService = RoomService,
}
