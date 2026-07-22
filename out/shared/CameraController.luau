-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local Workspace = _services.Workspace
local DEFAULT_DURATION = 0.35
local camera = Workspace.CurrentCamera
-- Zoom distances (studs from the camera subject) snapped on each transition:
-- dezoomed to frame the rocket + a bit of the room when the camera goes to the
-- rocket, and back to the Roblox default when it returns to the player.
local ROCKET_VIEW_DISTANCE = 35
local DEFAULT_VIEW_DISTANCE = 12.5
-- How long the zoom stays locked at the snapped distance before the player regains
-- free zoom control (one snap, then released).
local ZOOM_SNAP_HOLD = 0.1
local previousCameraType
-- ── Rocket follow camera ───────────────────────────────────────────────────────
-- During the button/rocket flow the camera uses the default Roblox camera
-- (CameraType.Custom) with its CameraSubject pointed at the rocket pivot
-- (CameraParentPart) instead of the player. The player keeps native camera
-- controls (rotate/zoom), and because the MovableModel carries CameraParentPart
-- up with it, the camera follows the rocket as it climbs with no extra code.
-- The default Roblox camera subject (the player's Humanoid) so we can hand the
-- camera back to the player after the rocket flow.
local function playerCameraSubject()
	local character = Players.LocalPlayer.Character
	local _humanoid = character
	if _humanoid ~= nil then
		_humanoid = _humanoid:FindFirstChildOfClass("Humanoid")
	end
	local humanoid = _humanoid
	if humanoid then
		return humanoid
	end
	local _hrp = character
	if _hrp ~= nil then
		_hrp = _hrp:FindFirstChild("HumanoidRootPart")
	end
	local hrp = _hrp
	local _result = hrp
	if _result ~= nil then
		_result = _result:IsA("BasePart")
	end
	return if _result then hrp else nil
end
-- Snap the default Roblox camera to a fixed zoom distance, then release the lock so
-- the player keeps free zoom control. Pinning Min == Max forces the distance; the
-- PlayerModule eases into it (no hard pop). Restored next tick to the captured limits.
local function snapZoomDistance(distance)
	local player = Players.LocalPlayer
	local prevMin = player.CameraMinZoomDistance
	local prevMax = player.CameraMaxZoomDistance
	player.CameraMinZoomDistance = distance
	player.CameraMaxZoomDistance = distance
	task.delay(ZOOM_SNAP_HOLD, function()
		player.CameraMinZoomDistance = prevMin
		player.CameraMaxZoomDistance = prevMax
	end)
end
local CameraController = {}
do
	local _container = CameraController
	local function SetCinematic()
		camera.CameraType = Enum.CameraType.Scriptable
	end
	_container.SetCinematic = SetCinematic
	local function AnimateTo(targetCFrame, duration)
		if duration == nil then
			duration = DEFAULT_DURATION
		end
		local tween = TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = targetCFrame,
		})
		tween:Play()
		tween.Completed:Wait()
	end
	_container.AnimateTo = AnimateTo
	-- Point the default Roblox camera at the rocket: native controls, but the camera
	-- follows subjectPart (CameraParentPart) so it tracks the rocket as it climbs.
	-- posCFrame is unused now that the native camera owns positioning — kept so the
	-- call site (ButtonMenuBehavior) stays unchanged.
	local StopOrbit
	local function StartOrbit(_posCFrame, subjectPart)
		StopOrbit()
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = subjectPart
		-- Pull back so the player sees the rocket plus a bit of the room before launch.
		snapZoomDistance(ROCKET_VIEW_DISTANCE)
	end
	_container.StartOrbit = StartOrbit
	function StopOrbit()
		-- Native rocket-follow has no render loop/connections to tear down; the camera
		-- subject is restored by BringBackPlayerCamera. Kept so call sites are unchanged.
	end
	_container.StopOrbit = StopOrbit
	local function BringBackPlayerCamera(duration)
		if duration == nil then
			duration = DEFAULT_DURATION
		end
		-- From a Scriptable cinematic (loss) tween smoothly back to the player;
		-- from the native rocket-follow there's nothing to tween — handing the subject
		-- back to the player is the native return.
		if camera.CameraType == Enum.CameraType.Scriptable then
			local _result = Players.LocalPlayer.Character
			if _result ~= nil then
				_result = _result:GetPivot()
			end
			AnimateTo(_result, duration)
		end
		StopOrbit()
		local subject = playerCameraSubject()
		if subject then
			camera.CameraSubject = subject
		end
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
		-- Classic reset: snap the zoom back to the default distance behind the player
		-- (the rocket view left the camera dezoomed).
		snapZoomDistance(DEFAULT_VIEW_DISTANCE)
	end
	_container.BringBackPlayerCamera = BringBackPlayerCamera
end
return {
	CameraController = CameraController,
}
