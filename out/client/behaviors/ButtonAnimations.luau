-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
-- Character animations for the button game, played on the local player's rig.
--
-- IMPORTANT: every id below MUST be owned by (or shared with) the experience's
-- creator — the group 963505568. Otherwise Roblox refuses to load it and the
-- track plays with Length 0 (nothing visible), logging:
--   "The experience doesn't have access permission to use asset id ..."
--
-- An empty id is treated as "not provided yet" and simply does nothing, so the
-- remaining animations can be filled in without breaking the others.
local ANIM_IDS = {
	interact = "rbxassetid://123442755794873",
	quit = "rbxassetid://93300469810162",
	hold = "rbxassetid://100517121510078",
	release = "rbxassetid://70993299432318",
	parry = "rbxassetid://84361846884673",
}
-- Freeze a held pose this many seconds before the clip's natural end. Stopping
-- just short keeps a non-looped track from auto-stopping (which blends back to
-- the default idle), so it holds its final frame instead.
local FREEZE_EPSILON = 0.05
-- Give up trying to freeze if the asset never reports a Length (e.g. an id not
-- owned by the group, see above) so the watcher can't spin forever.
local LOAD_TIMEOUT = 3
-- One AnimationTrack per name, lazily loaded against the current character's
-- Animator. The cache is dropped when the character changes (respawn).
local loadedFor
local tracks = {}
-- The held pose currently frozen on its last frame (interact/hold). One-shots
-- (quit/release/parry) are fire-and-forget and intentionally not tracked here,
-- so a later stop() — or the next held pose — never cuts them short.
local currentHold
-- Heartbeat watcher that pins the held pose on its last frame, if active.
local freezeConn
local function getAnimator()
	local character = Players.LocalPlayer.Character
	local _humanoid = character
	if _humanoid ~= nil then
		_humanoid = _humanoid:FindFirstChildOfClass("Humanoid")
	end
	local humanoid = _humanoid
	local _result = humanoid
	if _result ~= nil then
		_result = _result:FindFirstChildOfClass("Animator")
	end
	return _result
end
local function getTrack(name)
	local id = ANIM_IDS[name]
	if id == "" then
		return nil
	end
	local animator = getAnimator()
	if not animator then
		return nil
	end
	-- Drop stale tracks if the character respawned since they were loaded.
	local character = animator:FindFirstAncestorOfClass("Model")
	if character ~= loadedFor then
		table.clear(tracks)
		loadedFor = character
	end
	local _name = name
	local track = tracks[_name]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		local _name_1 = name
		local _track = track
		tracks[_name_1] = _track
	end
	return track
end
local function cancelFreeze()
	local _result = freezeConn
	if _result ~= nil then
		_result:Disconnect()
	end
	freezeConn = nil
end
-- Watch the playing track and pin it on its last frame (speed 0) so the pose
-- holds. Self-cancels once frozen, when the pose is replaced, or if the asset
-- never loads.
local function freezeOnLastFrame(name, track)
	cancelFreeze()
	local started = os.clock()
	freezeConn = RunService.Heartbeat:Connect(function()
		if currentHold ~= name then
			cancelFreeze()
			return nil
		end
		local length = track.Length
		if length == 0 then
			if os.clock() - started > LOAD_TIMEOUT then
				cancelFreeze()
			end
			return nil
		end
		if track.TimePosition >= length - FREEZE_EPSILON then
			track:AdjustSpeed(0)
			cancelFreeze()
		end
	end)
end
-- Stop only the held pose (idempotent). Leaves one-shots untouched.
local function stopHold()
	cancelFreeze()
	if currentHold == nil then
		return nil
	end
	local _currentHold = currentHold
	local _result = tracks[_currentHold]
	if _result ~= nil then
		_result:Stop()
	end
	currentHold = nil
end
-- Stop everything we play (held pose + any in-flight one-shot) and hand the rig
-- back to Roblox's default animations.
local function stopAll()
	cancelFreeze()
	currentHold = nil
	-- ▼ ReadonlyMap.forEach ▼
	local _callback = function(track)
		return track:Stop()
	end
	for _k, _v in tracks do
		_callback(_v, _k, tracks)
	end
	-- ▲ ReadonlyMap.forEach ▲
end
-- Play a clip once, then hold its last frame until it's replaced or stopped.
local function playHeld(name)
	if currentHold == name then
		return nil
	end
	stopHold()
	local track = getTrack(name)
	if not track then
		return nil
	end
	track.Looped = false
	track.TimePosition = 0
	track:Play(0.1, 1, 1)
	currentHold = name
	freezeOnLastFrame(name, track)
end
-- Play a clip once and let it blend back to the default Roblox animations at its
-- natural end. Replaces any held pose; not tracked, so stop() can't cut it.
local function playOnce(name)
	stopHold()
	local track = getTrack(name)
	if not track then
		return nil
	end
	track.Looped = false
	track.TimePosition = 0
	track:Play(0.1, 1, 1)
end
-- Public API — called from the button behaviors at each gameplay transition.
local ButtonAnimations = {
	playInteract = function()
		return playHeld("interact")
	end,
	playQuit = function()
		return playOnce("quit")
	end,
	playHold = function()
		return playHeld("hold")
	end,
	playRelease = function()
		return playOnce("release")
	end,
	playParry = function()
		return playOnce("parry")
	end,
	stop = function()
		return stopHold()
	end,
	restoreDefault = function()
		return stopAll()
	end,
}
return {
	ButtonAnimations = ButtonAnimations,
}
