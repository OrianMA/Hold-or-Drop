-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local Room = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "Room").Room
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local NeonPipeColors = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "NeonPipeColors").NeonPipeColors
local RoomSpotlights = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RoomSpotlights").RoomSpotlights
-- Owns the player ↔ room mapping (the "player-only" domain).
--
-- At server start it scans Workspace/PlayerZones for P{n} folders (one Button
-- model each) and turns each into a Room. Players are assigned the first free
-- room in order on join and released on leave. The billboard of an occupied
-- room mirrors the occupant's EffectiveBaseCash; empty rooms read "Empty".
--
-- The actual button gameplay (ButtonModule) consults getRooms()/owns() — this
-- service never touches the hold/risk loop.
local PLAYER_ZONES = "PlayerZones"
local rooms = {}
local roomByPlayer = {}
-- While a player is assigned, we mirror live BaseCash changes onto their room's
-- billboard (covers the DataStore load landing after the initial assign).
local baseCashConns = {}
-- Teleport the occupant onto their room's spawn part on every (re)spawn.
local spawnConns = {}
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
-- Place a character on top of a spawn part.
local function teleportToSpawn(character, spawn)
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then
		return nil
	end
	local playerHeight = character:GetExtentsSize().Y
	local _cFrame = spawn.CFrame
	local _vector3 = Vector3.new(0, spawn.Size.Y / 2 + playerHeight / 2, 0)
	hrp.CFrame = _cFrame + _vector3
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
	-- Tells this player's client which prompt to enable (RoomPromptController).
	player:SetAttribute("AssignedRoom", room.name)
	room:setGainCash(PlayerProgressionService:get(player, "EffectiveBaseCash"))
	-- Light this slot's neon pipe + spotlight in the room's colour.
	NeonPipeColors:setOccupied(room.name)
	RoomSpotlights:setOccupied(room.name)
	-- Teleport the player onto their room's spawn part on every (re)spawn, and move
	-- an already-spawned character now (service init with players already in-game).
	local spawnPart = room.spawnPart
	if spawnPart then
		local spawnConn = player.CharacterAdded:Connect(function(character)
			return teleportToSpawn(character, spawnPart)
		end)
		local _player_1 = player
		spawnConns[_player_1] = spawnConn
		if player.Character then
			teleportToSpawn(player.Character, spawnPart)
		end
	end
	local conn = player:GetAttributeChangedSignal("EffectiveBaseCash"):Connect(function()
		room:setGainCash(PlayerProgressionService:get(player, "EffectiveBaseCash"))
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
	local spawnConn = spawnConns[_player_1]
	if spawnConn then
		spawnConn:Disconnect()
		local _player_2 = player
		spawnConns[_player_2] = nil
	end
	local _player_2 = player
	local room = roomByPlayer[_player_2]
	if not room then
		return nil
	end
	room:release()
	local _player_3 = player
	roomByPlayer[_player_3] = nil
	player:SetAttribute("AssignedRoom", "")
	-- Slot freed — grey its neon pipe + turn the spotlight off.
	NeonPipeColors:setEmpty(room.name)
	RoomSpotlights:setEmpty(room.name)
end
local RoomService = {
	init = function(self)
		-- Grey every neon pipe + turn every spotlight off — empty baseline before
		-- any assignment below.
		NeonPipeColors:init()
		RoomSpotlights:init()
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
		-- The CommunityJoinPart prompt is now driven entirely client-side: the client
		-- opens the native GroupService:PromptJoinAsync card and fires
		-- CommunityJoinedEvent on success (wired in BoostService). No server wiring here.
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
