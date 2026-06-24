-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Workspace = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Workspace
local _RoomColors = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RoomColors")
local EMPTY_COLOR = _RoomColors.EMPTY_COLOR
local ROOM_COLORS = _RoomColors.ROOM_COLORS
-- Colours the Workspace/Environment/NeonPipe/P{n} pipes to match the player
-- holding that room slot. The room name (P1..P5) maps 1:1 to a NeonPipe/P{n}
-- folder, so the colour is chosen by slot, not by join order.
--
-- Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name)
-- on release. init() greys every pipe — the empty / server-start baseline.
-- Colours are slot-keyed and shared with the room spotlights — see RoomColors.
local ENVIRONMENT = "Environment"
local NEON_PIPE = "NeonPipe"
-- Incremented on each successful purchase for a slot; the client (NeonPipePulse)
-- watches this attribute to run the travelling-segment animation.
local PULSE_ATTR = "Pulse"
-- Walk each P{n} folder once and cache its parts — colour changes are frequent
-- (every assign/release) but the part set never changes at runtime.
local partsByRoom = {}
local function neonPipeFolder()
	local _result = Workspace:FindFirstChild(ENVIRONMENT)
	if _result ~= nil then
		_result = _result:FindFirstChild(NEON_PIPE)
	end
	return _result
end
local function resolveParts(roomName)
	local _roomName = roomName
	local cached = partsByRoom[_roomName]
	if cached then
		return cached
	end
	local parts = {}
	local _folder = neonPipeFolder()
	if _folder ~= nil then
		_folder = _folder:FindFirstChild(roomName)
	end
	local folder = _folder
	if folder then
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	local _roomName_1 = roomName
	partsByRoom[_roomName_1] = parts
	return parts
end
local function paint(roomName, color)
	for _, part in resolveParts(roomName) do
		part.Color = color
	end
end
local NeonPipeColors = {
	init = function(self)
		local root = neonPipeFolder()
		if not root then
			warn(`NeonPipeColors: Workspace/{ENVIRONMENT}/{NEON_PIPE} not found`)
			return nil
		end
		for _, folder in root:GetChildren() do
			paint(folder.Name, EMPTY_COLOR)
		end
	end,
	setOccupied = function(self, roomName)
		local _exp = roomName
		local _roomName = roomName
		local _condition = ROOM_COLORS[_roomName]
		if _condition == nil then
			_condition = EMPTY_COLOR
		end
		paint(_exp, _condition)
	end,
	setEmpty = function(self, roomName)
		paint(roomName, EMPTY_COLOR)
	end,
	pulse = function(self, roomName)
		local _folder = neonPipeFolder()
		if _folder ~= nil then
			_folder = _folder:FindFirstChild(roomName)
		end
		local folder = _folder
		if not folder then
			return nil
		end
		local _condition = (folder:GetAttribute(PULSE_ATTR))
		if _condition == nil then
			_condition = 0
		end
		local current = _condition
		folder:SetAttribute(PULSE_ATTR, current + 1)
	end,
}
return {
	NeonPipeColors = NeonPipeColors,
}
