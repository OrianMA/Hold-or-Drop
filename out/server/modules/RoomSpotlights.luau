-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Workspace = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Workspace
local _RoomColors = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RoomColors")
local EMPTY_COLOR = _RoomColors.EMPTY_COLOR
local roomColor = _RoomColors.roomColor
-- Drives the per-room spotlight (Workspace/PlayerZones/P{n}/Environment/SpotLight) from room
-- occupancy, mirroring NeonPipeColors: the lamp lights up in the slot colour while
-- the room is owned and turns OFF when empty — same on/off feel as the neon pipes.
--
-- Each SpotLight model has one Neon `LightSource` part (the glowing lens) holding a
-- single `SurfaceLight` (the projected cone). We tint the lens + light together and
-- toggle the SurfaceLight; the metal/plastic housing parts are left untouched.
--
-- Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name) on
-- release. init() turns every lamp off — the empty / server-start baseline.
local PLAYER_ZONES = "PlayerZones"
local ENVIRONMENT = "Environment"
local SPOTLIGHT = "SpotLight"
local LIGHT_SOURCE = "LightSource"
-- Resolve + cache each room's lamp once — the instance set never changes at runtime.
-- Cached `undefined` means "looked up, not found" so we warn only once per slot.
local lampByRoom = {}
local function resolveLamp(roomName)
	local _roomName = roomName
	if lampByRoom[_roomName] ~= nil then
		local _roomName_1 = roomName
		return lampByRoom[_roomName_1]
	end
	local _model = Workspace:FindFirstChild(PLAYER_ZONES)
	if _model ~= nil then
		_model = _model:FindFirstChild(roomName)
		if _model ~= nil then
			_model = _model:FindFirstChild(ENVIRONMENT)
			if _model ~= nil then
				_model = _model:FindFirstChild(SPOTLIGHT)
			end
		end
	end
	local model = _model
	local _lens = model
	if _lens ~= nil then
		_lens = _lens:FindFirstChild(LIGHT_SOURCE)
	end
	local lens = _lens
	local _light = lens
	if _light ~= nil then
		_light = _light:FindFirstChildWhichIsA("SurfaceLight")
	end
	local light = _light
	local lamp
	if lens and lens:IsA("BasePart") and light then
		lamp = {
			lens = lens,
			light = light,
		}
	else
		warn(`RoomSpotlights: {roomName} missing SpotLight/{LIGHT_SOURCE}/SurfaceLight`)
	end
	local _roomName_1 = roomName
	local _lamp = lamp
	lampByRoom[_roomName_1] = _lamp
	return lamp
end
local function setLamp(roomName, color, on)
	local lamp = resolveLamp(roomName)
	if not lamp then
		return nil
	end
	lamp.lens.Color = color
	lamp.light.Color = color
	lamp.light.Enabled = on
end
local RoomSpotlights = {
	init = function(self)
		local zones = Workspace:FindFirstChild(PLAYER_ZONES)
		if not zones then
			warn(`RoomSpotlights: Workspace/{PLAYER_ZONES} not found`)
			return nil
		end
		for _, zone in zones:GetChildren() do
			local _result = zone:FindFirstChild(ENVIRONMENT)
			if _result ~= nil then
				_result = _result:FindFirstChild(SPOTLIGHT)
			end
			if _result then
				setLamp(zone.Name, EMPTY_COLOR, false)
			end
		end
	end,
	setOccupied = function(self, roomName)
		setLamp(roomName, roomColor(roomName), true)
	end,
	setEmpty = function(self, roomName)
		setLamp(roomName, EMPTY_COLOR, false)
	end,
}
return {
	RoomSpotlights = RoomSpotlights,
}
