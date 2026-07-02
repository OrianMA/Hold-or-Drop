-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Redirects the player's NATIVE left/right movement to the flying rocket. During a run
-- the character is anchored (ButtonModule.teleportPlayer), so the movement input never
-- walks it — we read the raw move vector from Roblox's own ControlModule, which reports
-- input identically across keyboard (A/D), the mobile thumbstick and gamepad sticks,
-- independent of the camera. Reusing the native controls means the feature works on
-- every device with no extra UI.
--
-- We quantise the horizontal axis to -1 (left) / 0 / +1 (right) and fire RocketSteerEvent
-- only when it changes, so a whole flight costs a handful of RemoteEvent calls. The server
-- (RocketLauncher.setSteer) does the actual, smooth, altitude-scaled rolling.
-- Minimal shape of the ControlModule API we use (GetControls():GetMoveVector()).
-- Ignore tiny thumbstick drift so a resting stick reads as "no steer".
local DEADZONE = 0.15
local controls
local enabled = false
local lastSent = 0
local pollConn
-- Roblox's ControlModule lives in the player's replicated PlayerModule. Require it once
-- and cache the Controls object (native input, all devices).
local function getControls()
	if controls then
		return controls
	end
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local _result = playerScripts
	if _result ~= nil then
		_result = _result:FindFirstChild("PlayerModule")
	end
	local moduleScript = _result
	if not moduleScript then
		return nil
	end
	local playerModule = require(moduleScript)
	controls = playerModule:GetControls()
	return controls
end
local function poll()
	if not enabled then
		return nil
	end
	local c = getControls()
	if not c then
		return nil
	end
	local x = c:GetMoveVector().X
	local dir = if x > DEADZONE then 1 elseif x < -DEADZONE then -1 else 0
	if dir ~= lastSent then
		lastSent = dir
		Events.RocketSteerEvent:FireServer(dir)
	end
end
local RocketSteerController = {
	start = function(self)
		if enabled then
			return nil
		end
		enabled = true
		lastSent = 0
		local _result = pollConn
		if _result ~= nil then
			_result:Disconnect()
		end
		pollConn = RunService.RenderStepped:Connect(poll)
	end,
	stop = function(self)
		if not enabled then
			return nil
		end
		enabled = false
		local _result = pollConn
		if _result ~= nil then
			_result:Disconnect()
		end
		pollConn = nil
		if lastSent ~= 0 then
			lastSent = 0
			Events.RocketSteerEvent:FireServer(0)
		end
	end,
}
return {
	RocketSteerController = RocketSteerController,
}
