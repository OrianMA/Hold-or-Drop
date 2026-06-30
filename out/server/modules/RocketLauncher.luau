-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local ROCKET_ACCEL = _RocketGameConfig.ROCKET_ACCEL
local ROCKET_MAX_SPEED = _RocketGameConfig.ROCKET_MAX_SPEED
-- Drives the per-room rocket (the MovableModel): it rises while the button is held
-- with a slow, accelerating, real-rocket feel, lights its engine Fire (NitroParticles)
-- while moving, and physically blows the rocket apart on a loss.
--
-- Moving the whole MovableModel via PivotTo carries its CameraPosPart /
-- CameraParentPart up with it, so the client's orbit camera (which reads the pivot
-- live) follows the rocket automatically — see CameraController.StartOrbit.
local EXPLOSION_EMITTER = "ExplosionParticles"
local PARTICLES_PARENT = "ParticlesParentPart"
local EXPLOSION_PARTICLE_COUNT = 60
-- Part inside the rocket holding the engine Fire(s) — lit while the rocket moves.
local NITRO_PART = "NitroParticles"
-- The rocket body model inside the MovableModel — these are the parts that physically
-- break apart on an explosion (the Camera*/Particles helper parts stay anchored so the
-- orbit camera keeps holding on the blast site).
local ROCKET_MODEL = "RocketLvl1"
-- ── Physical explosion tuning ───────────────────────────────────────────────────
-- Height-based gravity (world-space Y, studs): above SPACE_HEIGHT the debris is in
-- space and weightless; through the SPACE_HEIGHT→GROUND_HEIGHT band gravity fades in;
-- below GROUND_HEIGHT it falls under full earth gravity.
local SPACE_HEIGHT = 95
local GROUND_HEIGHT = 50
-- Outward burst applied to every debris part the instant the rocket bursts apart.
-- The radial spread is horizontal-only and the vertical kick scales with the part's
-- height inside the rocket, so every part is flung UP (never any -Y velocity): the
-- nose is launched hardest, the lowest parts barely lift.
local BURST_SPEED = 45
local BURST_SPEED_VARIANCE = 25
local BURST_UP_MIN = 5
local BURST_UP_MAX = 95
local BURST_SPIN = 18
-- One rocket body part with the data needed to fully restore it after a physical
-- explosion: its pose relative to the launch pad and its authored collision flag.
local states = {}
-- The authored launch-pad pivot, captured once per room so every launch resets to
-- the exact same spot regardless of where a previous run left the model.
local originalPivots = {}
-- The rocket-body parts (RocketLvl1 descendants) with their pad-relative pose,
-- captured once per room so a physical explosion can be fully undone on reset.
local rocketParts = {}
-- The active debris-physics Heartbeat while the rocket is mid-explosion.
local debrisConns = {}
local function getRocketModel(room)
	return room.movableModel:FindFirstChild(ROCKET_MODEL)
end
-- Capture the rocket body parts and their pad-relative pose once per room. Must be
-- called while the model sits on its launch pad (so the captured offsets are the
-- on-pad arrangement we restore to).
local function captureRocketParts(room)
	local _room = room
	if rocketParts[_room] ~= nil then
		return nil
	end
	local model = getRocketModel(room)
	if not model then
		return nil
	end
	local _room_1 = room
	local _condition = originalPivots[_room_1]
	if _condition == nil then
		_condition = room.movableModel:GetPivot()
	end
	local padPivot = _condition
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local _arg0 = {
				part = d,
				offset = padPivot:ToObjectSpace(d.CFrame),
				canCollide = d.CanCollide,
			}
			table.insert(parts, _arg0)
		end
	end
	local _room_2 = room
	rocketParts[_room_2] = parts
end
-- Re-anchor and re-pose any exploded debris back onto the pad, restoring authored
-- collision and zeroing physics — leaves the rocket ready for the next launch.
local function restoreRocketParts(room)
	local _room = room
	local conn = debrisConns[_room]
	if conn then
		conn:Disconnect()
		local _room_1 = room
		debrisConns[_room_1] = nil
	end
	local _room_1 = room
	local parts = rocketParts[_room_1]
	local _room_2 = room
	local padPivot = originalPivots[_room_2]
	if not parts or not padPivot then
		return nil
	end
	for _, rp in parts do
		local part = rp.part
		if not part.Parent then
			continue
		end
		part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		part.Anchored = true
		part.CanCollide = rp.canCollide
		local _offset = rp.offset
		part.CFrame = padPivot * _offset
	end
end
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
	restoreRocketParts(room)
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
		captureRocketParts(room)
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
		-- Inherit the rocket's current ascent speed before halting the ascent loop, so the
		-- debris keeps rising instead of stopping dead the instant it explodes.
		local _room = room
		local _result = states[_room]
		if _result ~= nil then
			_result = _result.velocity
		end
		local _condition = _result
		if _condition == nil then
			_condition = 0
		end
		local ascentVelocity = _condition
		stopRoom(room)
		-- Particle burst (existing visual cue).
		local ppp = room.movableModel:FindFirstChild(PARTICLES_PARENT)
		local _emitter = ppp
		if _emitter ~= nil then
			_emitter = _emitter:FindFirstChild(EXPLOSION_EMITTER)
		end
		local emitter = _emitter
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter:Emit(EXPLOSION_PARTICLE_COUNT)
		end
		local _room_1 = room
		local parts = rocketParts[_room_1]
		if not parts or #parts == 0 then
			return nil
		end
		local model = getRocketModel(room)
		local center = (model or room.movableModel):GetPivot().Position
		local gravity = Workspace.Gravity
		-- Vertical extent of the rocket so the upward kick can scale by height: the
		-- lowest part lifts by BURST_UP_MIN, the nose by BURST_UP_MAX. No part ever
		-- gets a downward (-Y) velocity.
		local minY = math.huge
		local maxY = -math.huge
		for _, rp in parts do
			local y = rp.part.Position.Y
			if y < minY then
				minY = y
			end
			if y > maxY then
				maxY = y
			end
		end
		local span = math.max(maxY - minY, 0.05)
		-- Unanchor each body part and fling it outward: horizontal-only radial spread
		-- (so the burst never pushes anything down) plus a height-scaled upward kick and
		-- random spin, so the rocket reads as blown apart and launched up. Debris is
		-- non-collidable while flying so it can't snag on room geometry or jitter.
		for _, rp in parts do
			local part = rp.part
			if not part.Parent then
				continue
			end
			part.Anchored = false
			part.CanCollide = false
			local away = part.Position - center
			local flat = Vector3.new(away.X, 0, away.Z)
			local dir = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1).Unit
			local speed = BURST_SPEED + math.random() * BURST_SPEED_VARIANCE
			local heightFactor = (part.Position.Y - minY) / span
			local up = BURST_UP_MIN + heightFactor * (BURST_UP_MAX - BURST_UP_MIN)
			local _exp = dir * speed
			local _vector3 = Vector3.new(0, up, 0)
			part.AssemblyLinearVelocity = _exp + _vector3
			-- Radial burst + an upward kick + the inherited ascent momentum → the rocket
			-- keeps climbing as it breaks apart, until height-based gravity pulls it back.
			-- part.AssemblyLinearVelocity = dir.mul(speed).add(new Vector3(0, BURST_UP_BIAS + ascentVelocity, 0));
			part.AssemblyAngularVelocity = Vector3.new((math.random() * 2 - 1) * BURST_SPIN, (math.random() * 2 - 1) * BURST_SPIN, (math.random() * 2 - 1) * BURST_SPIN)
		end
		-- Height-based gravity. Roblox already pulls `gravity` studs/s² down on every
		-- unanchored part; each frame we add back `gravity*(1-scale)` upward so the net
		-- downward pull is `gravity*scale`: scale 0 above SPACE_HEIGHT (weightless space),
		-- ramping to 1 at GROUND_HEIGHT and staying 1 below (full earth gravity).
		local conn = RunService.Heartbeat:Connect(function(dt)
			for _, rp in parts do
				local part = rp.part
				if not part.Parent or part.Anchored then
					continue
				end
				local y = part.Position.Y
				local scale
				if y >= SPACE_HEIGHT then
					scale = 0
				elseif y <= GROUND_HEIGHT then
					scale = 1
				else
					scale = (SPACE_HEIGHT - y) / (SPACE_HEIGHT - GROUND_HEIGHT)
				end
				local cancel = gravity * (1 - scale) * dt
				if cancel > 0 then
					local _assemblyLinearVelocity = part.AssemblyLinearVelocity
					local _vector3 = Vector3.new(0, cancel, 0)
					part.AssemblyLinearVelocity = _assemblyLinearVelocity + _vector3
				end
			end
		end)
		local _room_2 = room
		debrisConns[_room_2] = conn
	end,
}
return {
	RocketLauncher = RocketLauncher,
}
