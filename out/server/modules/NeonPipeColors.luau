-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Workspace = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Workspace
-- Colours the Workspace/Environment/NeonPipe/P{n} pipes to match the player
-- holding that room slot. The room name (P1..P5) maps 1:1 to a NeonPipe/P{n}
-- folder, so the colour is chosen by slot, not by join order.
--
-- Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name)
-- on release. init() greys every pipe — the empty / server-start baseline.
-- --- Tunable colours (edit here) --------------------------------------------
local EMPTY_COLOR = Color3.fromRGB(120, 120, 120)
-- Room/folder name → pipe colour. Add/rename entries to match PlayerZones.
local ROOM_COLORS = {
	P1 = Color3.fromRGB(0, 255, 242),
	P2 = Color3.fromRGB(255, 15, 15),
	P3 = Color3.fromRGB(255, 250, 0),
	P4 = Color3.fromRGB(15, 255, 56),
	P5 = Color3.fromRGB(181, 23, 255),
}
-- ----------------------------------------------------------------------------
local ENVIRONMENT = "Environment"
local NEON_PIPE = "NeonPipe"
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
}
return {
	NeonPipeColors = NeonPipeColors,
}
