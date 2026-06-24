-- Compiled with roblox-ts v3.0.0
-- Single source of truth for the per-room slot colours. Both the neon pipes
-- (NeonPipeColors) and the room spotlights (RoomSpotlights) read from here, so a
-- retune stays in one place and the spotlight colour always matches the neon one.
-- Slot has no player — grey. Shared "off" baseline for pipes and spotlights.
local EMPTY_COLOR = Color3.fromRGB(120, 120, 120)
-- Room/folder name (P1..P5) → slot colour. Add/rename entries to match PlayerZones.
local ROOM_COLORS = {
	P1 = Color3.fromRGB(0, 255, 242),
	P2 = Color3.fromRGB(255, 15, 15),
	P3 = Color3.fromRGB(255, 250, 0),
	P4 = Color3.fromRGB(15, 255, 56),
	P5 = Color3.fromRGB(181, 23, 255),
}
-- Colour for a slot, falling back to grey for an unknown name.
local function roomColor(roomName)
	local _roomName = roomName
	local _condition = ROOM_COLORS[_roomName]
	if _condition == nil then
		_condition = EMPTY_COLOR
	end
	return _condition
end
return {
	roomColor = roomColor,
	EMPTY_COLOR = EMPTY_COLOR,
	ROOM_COLORS = ROOM_COLORS,
}
