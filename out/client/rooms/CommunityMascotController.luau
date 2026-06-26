-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local Workspace = _services.Workspace
-- Community mascot, per room. The GrorianStudioMascot MeshPart sits directly in
-- each room folder (PlayerZones/P{n}/GrorianStudioMascot) and does two things,
-- 100 % client / presentation — no server logic:
--
--   • Idle float — a gentle up/down hover (looping Position tween). The MeshPart is
--     anchored in Studio, so a local tween renders cleanly without fighting physics.
--   • Per-player visibility — shown ONLY on the player's own room; on every other
--     room it is made fully transparent. Exactly the same rule the CommunityJoinPart
--     elements follow (see CommunityJoinController), driven by the replicated
--     AssignedRoom attribute. Client-local writes don't replicate, so each player
--     only affects their own view.
--
-- StreamingEnabled is ON, so a mascot can stream IN at any time (a fresh instance)
-- and OUT again. We therefore discover via WaitForChild / ChildAdded down the
-- PlayerZones → P{n} → GrorianStudioMascot chain — never a one-shot FindFirstChild
-- at boot — (re)start the float and (re)apply visibility each time a mascot appears.
local PLAYER_ZONES = "PlayerZones"
local MASCOT_NAME = "GrorianStudioMascot"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
-- How far (studs) the mascot rises from its resting position, and how long one
-- rise (or fall) takes. Slow + smooth = a gentle hover.
local FLOAT_HEIGHT = 1
local FLOAT_DURATION = 2
local floatInfo = TweenInfo.new(FLOAT_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- Start a looping float on one anchored mascot from its current resting position.
local function startFloat(mascot)
	local basePosition = mascot.Position
	local _exp = mascot
	local _object = {}
	local _left = "Position"
	local _vector3 = Vector3.new(0, FLOAT_HEIGHT, 0)
	_object[_left] = basePosition + _vector3
	local tween = TweenService:Create(_exp, floatInfo, _object)
	-- A small random phase so the mascots across rooms don't bob in lockstep.
	task.spawn(function()
		task.wait(math.random() * FLOAT_DURATION)
		if mascot.Parent ~= nil then
			tween:Play()
		end
	end)
end
local function init()
	local player = Players.LocalPlayer
	-- Keyed by room name so a mascot that streams out then back in (a fresh
	-- instance) simply replaces the stale entry.
	local entries = {}
	-- Visible only on our own room — fully transparent on every other.
	local applyVisibility = function(entry)
		if entry.mascot.Parent == nil then
			return nil
		end
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		local own = entry.roomName == assigned
		entry.mascot.Transparency = if own then entry.defaultTransparency else 1
	end
	local evaluate = function()
		for _, entry in entries do
			applyVisibility(entry)
		end
	end
	-- Register (or refresh) a room's mascot: start its float and apply visibility now.
	local registerMascot = function(roomName, mascot)
		local entry = {
			roomName = roomName,
			mascot = mascot,
			defaultTransparency = mascot.Transparency,
		}
		local _roomName = roomName
		entries[_roomName] = entry
		applyVisibility(entry)
		startFloat(mascot)
	end
	-- Watch one room folder for its mascot (present now or streamed in later).
	local watchFolder = function(folder)
		local existing = folder:FindFirstChild(MASCOT_NAME)
		if existing and existing:IsA("BasePart") then
			registerMascot(folder.Name, existing)
		end
		folder.ChildAdded:Connect(function(child)
			if child.Name == MASCOT_NAME and child:IsA("BasePart") then
				registerMascot(folder.Name, child)
			end
		end)
	end
	-- Server-driven — re-render whenever ownership changes (room (re)assignment).
	player:GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR):Connect(evaluate)
	-- Discovery runs off the main thread (WaitForChild may yield while the zones
	-- stream / replicate in).
	task.spawn(function()
		local zones = Workspace:WaitForChild(PLAYER_ZONES, 30)
		if not zones then
			warn("CommunityMascotController: Workspace/PlayerZones not found")
			return nil
		end
		for _, folder in zones:GetChildren() do
			watchFolder(folder)
		end
		-- Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded:Connect(function(folder)
			return watchFolder(folder)
		end)
	end)
end
return {
	init = init,
}
