-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RunService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").RunService
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local ROCKET_ACCEL = _RocketGameConfig.ROCKET_ACCEL
local ROCKET_MAX_SPEED = _RocketGameConfig.ROCKET_MAX_SPEED
-- Drives the per-room rocket (the MovableModel): it rises while the button is held
-- with a slow, accelerating, real-rocket feel, lights its engine Fire (NitroParticles)
-- while moving, and bursts an explosion on a loss.
--
-- Moving the whole MovableModel via PivotTo carries its CameraPosPart /
-- CameraParentPart up with it, so the client's orbit camera (which reads the pivot
-- live) follows the rocket automatically — see CameraController.StartOrbit.
local EXPLOSION_EMITTER = "ExplosionParticles"
local PARTICLES_PARENT = "ParticlesParentPart"
local EXPLOSION_PARTICLE_COUNT = 60
-- Part inside the rocket holding the engine Fire(s) — lit while the rocket moves.
local NITRO_PART = "NitroParticles"
local states = {}
-- The authored launch-pad pivot, captured once per room so every launch resets to
-- the exact same spot regardless of where a previous run left the model.
local originalPivots = {}
-- Light/extinguish the engine Fire(s) inside the rocket's NitroParticles part(s).
local function setNitroEnabled(room, enabled)
	for _, d in room.movableModel:GetDescendants() do
		if d:IsA("Fire") and d:FindFirstAncestor(NITRO_PART) ~= nil then
			d.Enabled = enabled
		end
	end
end
local function stopRoom(room)
	local _room = room
	local state = states[_room]
	if state then
		state.conn:Disconnect()
		local _room_1 = room
		states[_room_1] = nil
	end
	setNitroEnabled(room, false)
end
local function resetRoom(room)
	stopRoom(room)
	local _room = room
	local pivot = originalPivots[_room]
	if pivot then
		room.movableModel:PivotTo(pivot)
	end
end
local RocketLauncher = {
	launch = function(self, room, speedFactor)
		if speedFactor == nil then
			speedFactor = 1
		end
		local _room = room
		if not (originalPivots[_room] ~= nil) then
			local _room_1 = room
			local _arg1 = room.movableModel:GetPivot()
			originalPivots[_room_1] = _arg1
		end
		resetRoom(room)
		local maxSpeed = ROCKET_MAX_SPEED * speedFactor
		local accel = ROCKET_ACCEL * speedFactor
		local state = {
			conn = nil,
			velocity = 0,
		}
		state.conn = RunService.Heartbeat:Connect(function(dt)
			state.velocity = math.min(state.velocity + accel * dt, maxSpeed)
			local _movableModel = room.movableModel
			local _exp = room.movableModel:GetPivot()
			local _vector3 = Vector3.new(0, state.velocity * dt, 0)
			_movableModel:PivotTo(_exp + _vector3)
		end)
		local _room_1 = room
		states[_room_1] = state
		setNitroEnabled(room, true)
	end,
	stop = function(self, room)
		stopRoom(room)
	end,
	reset = function(self, room)
		resetRoom(room)
	end,
	explode = function(self, room)
		local ppp = room.movableModel:FindFirstChild(PARTICLES_PARENT)
		local _emitter = ppp
		if _emitter ~= nil then
			_emitter = _emitter:FindFirstChild(EXPLOSION_EMITTER)
		end
		local emitter = _emitter
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter:Emit(EXPLOSION_PARTICLE_COUNT)
		end
	end,
}
return {
	RocketLauncher = RocketLauncher,
}
