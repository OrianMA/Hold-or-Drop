-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local TweenService = _services.TweenService
local Workspace = _services.Workspace
-- Cosmetic idle animation for the community mascot: every room's
-- CommunityJoinPart holds a GrorianStudioMascot MeshPart that should gently float
-- up and down. 100 % client / presentation — no server logic, like the other
-- per-room visual controllers.
--
-- StreamingEnabled is ON, so a mascot can stream IN at any time (a fresh instance)
-- and OUT again. We therefore discover via WaitForChild / ChildAdded down the
-- PlayerZones → P{n} → CommunityJoinPart → GrorianStudioMascot chain — never a
-- one-shot FindFirstChild at boot — and (re)start the float each time a mascot
-- appears. The MeshPart is anchored in Studio, so a local Position tween renders
-- cleanly without fighting physics (client-only, never replicated).
local PLAYER_ZONES = "PlayerZones"
local COMMUNITY_JOIN_PART = "CommunityJoinPart"
local MASCOT_NAME = "GrorianStudioMascot"
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
-- Watch one CommunityJoinPart for its mascot (present now or streamed in later).
local function watchJoinPart(joinPart)
	local existing = joinPart:FindFirstChild(MASCOT_NAME)
	if existing and existing:IsA("BasePart") then
		startFloat(existing)
	end
	joinPart.ChildAdded:Connect(function(child)
		if child.Name == MASCOT_NAME and child:IsA("BasePart") then
			startFloat(child)
		end
	end)
end
-- Watch one room folder for its CommunityJoinPart (present now or streamed in later).
local function watchFolder(folder)
	local existing = folder:FindFirstChild(COMMUNITY_JOIN_PART)
	if existing then
		watchJoinPart(existing)
	end
	folder.ChildAdded:Connect(function(child)
		if child.Name == COMMUNITY_JOIN_PART then
			watchJoinPart(child)
		end
	end)
end
local function init()
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
