-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local Workspace = _services.Workspace
local DEFAULT_DURATION = 0.35
local camera = Workspace.CurrentCamera
local previousCameraType
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
	local Reset
	local function BringBackPlayerCamera(duration)
		if duration == nil then
			duration = DEFAULT_DURATION
		end
		local _result = Players.LocalPlayer.Character
		if _result ~= nil then
			_result = _result:GetPivot()
		end
		AnimateTo(_result, duration)
		Reset()
	end
	_container.BringBackPlayerCamera = BringBackPlayerCamera
	local function AnimateTween()
	end
	function Reset()
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
	end
end
return {
	CameraController = CameraController,
}
