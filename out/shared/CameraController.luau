-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
local Workspace = _services.Workspace
local DEFAULT_DURATION = 0.35
local camera = Workspace.CurrentCamera
local previousCameraType
-- ── Orbit camera ──────────────────────────────────────────────────────────────
-- Dynamic camera used during the button/rocket flow: the player rotates freely
-- (right-drag on PC, touch-drag on mobile) but the camera always looks at a pivot
-- part (CameraParentPart). The pivot position is read live each frame, so moving
-- the pivot (e.g. with the rocket) makes the camera follow automatically.
local ORBIT_BINDING = "HoldOrDropCameraOrbit"
local ORBIT_SENSITIVITY = 0.0075
local MIN_PITCH = math.rad(-15)
local MAX_PITCH = math.rad(80)
local orbitPivot
local orbitYaw = 0
local orbitPitch = 0
local orbitRadius = 0
local orbitConns = {}
local orbitDragging = false
local orbitTouch
local function orbitOffset()
	local horizontal = orbitRadius * math.cos(orbitPitch)
	return Vector3.new(horizontal * math.sin(orbitYaw), orbitRadius * math.sin(orbitPitch), horizontal * math.cos(orbitYaw))
end
local function applyOrbitDelta(dx, dy)
	orbitYaw -= dx * ORBIT_SENSITIVITY
	orbitPitch = math.clamp(orbitPitch - dy * ORBIT_SENSITIVITY, MIN_PITCH, MAX_PITCH)
end
local function orbitStep()
	if not orbitPivot then
		return nil
	end
	local pivotPos = orbitPivot.Position
	local _arg0 = orbitOffset()
	camera.CFrame = CFrame.lookAt(pivotPos + _arg0, pivotPos)
end
local function bindOrbitInput()
	local _orbitConns = orbitConns
	local _arg0 = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return nil
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbitDragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and orbitTouch == nil then
			orbitTouch = input
		end
	end)
	table.insert(_orbitConns, _arg0)
	local _orbitConns_1 = orbitConns
	local _arg0_1 = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and orbitDragging then
			applyOrbitDelta(input.Delta.X, input.Delta.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch and input == orbitTouch then
			applyOrbitDelta(input.Delta.X, input.Delta.Y)
		end
	end)
	table.insert(_orbitConns_1, _arg0_1)
	local _orbitConns_2 = orbitConns
	local _arg0_2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbitDragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input == orbitTouch then
			orbitTouch = nil
		end
	end)
	table.insert(_orbitConns_2, _arg0_2)
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
	-- Smoothly move to the start pose (looking at the pivot from posCFrame), then
	-- hand off to a live orbit the player can rotate. Always faces pivotPart.
	local StopOrbit
	local function StartOrbit(posCFrame, pivotPart)
		StopOrbit()
		camera.CameraType = Enum.CameraType.Scriptable
		local pivotPos = pivotPart.Position
		local delta = posCFrame.Position - pivotPos
		orbitRadius = delta.Magnitude
		orbitPitch = if orbitRadius > 0 then math.clamp(math.asin(math.clamp(delta.Y / orbitRadius, -1, 1)), MIN_PITCH, MAX_PITCH) else 0
		orbitYaw = math.atan2(delta.X, delta.Z)
		orbitPivot = pivotPart
		-- Entry transition to the seeded orbit pose (looking straight at the pivot),
		-- then start the per-frame loop so the pose matches seamlessly.
		local _arg0 = orbitOffset()
		local startPos = pivotPos + _arg0
		AnimateTo(CFrame.lookAt(startPos, pivotPos))
		RunService:BindToRenderStep(ORBIT_BINDING, Enum.RenderPriority.Camera.Value, orbitStep)
		bindOrbitInput()
	end
	_container.StartOrbit = StartOrbit
	function StopOrbit()
		if orbitPivot == nil and #orbitConns == 0 then
			return nil
		end
		pcall(function()
			return RunService:UnbindFromRenderStep(ORBIT_BINDING)
		end)
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(c)
			return c:Disconnect()
		end
		for _k, _v in orbitConns do
			_callback(_v, _k - 1, orbitConns)
		end
		-- ▲ ReadonlyArray.forEach ▲
		orbitConns = {}
		if orbitDragging then
			orbitDragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		orbitTouch = nil
		orbitPivot = nil
	end
	_container.StopOrbit = StopOrbit
	local Reset
	local function BringBackPlayerCamera(duration)
		if duration == nil then
			duration = DEFAULT_DURATION
		end
		StopOrbit()
		local _result = Players.LocalPlayer.Character
		if _result ~= nil then
			_result = _result:GetPivot()
		end
		AnimateTo(_result, duration)
		Reset()
	end
	_container.BringBackPlayerCamera = BringBackPlayerCamera
	function Reset()
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
	end
end
return {
	CameraController = CameraController,
}
