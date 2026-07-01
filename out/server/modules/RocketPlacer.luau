-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local ReplicatedStorage = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").ReplicatedStorage
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local _RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher")
local RocketLauncher = _RocketLauncher.RocketLauncher
local ROCKET_MODEL = _RocketLauncher.ROCKET_MODEL
local NITRO_PART = _RocketLauncher.NITRO_PART
-- Picks the right rocket for the room's occupant and instantiates it on the pad.
--
-- The rockets are authored in ReplicatedStorage/RocketModels as RocketLvl1..RocketLvlN.
-- The chosen level tracks the player's Rebirths count: rebirth N → RocketLvlN, clamped
-- to [1, N_rockets] (rebirth 0 falls back to Lvl1 since there is no Lvl0, and a rebirth
-- count above the number of rockets gets the highest one). The clone is renamed to the
-- stable ROCKET_MODEL name so RocketLauncher (§6.17) drives it regardless of its level.
local ROCKET_MODELS_FOLDER = "RocketModels"
local ROCKET_PREFIX = "RocketLvl"
-- rebirth count → 1-based rocket level, clamped to the number of authored rockets.
local function rocketLevelFor(rebirths, count)
	return math.clamp(rebirths, 1, count)
end
-- Remove the room's current rocket and drop the launcher caches that referenced it
-- (rooms are reused across occupants, so the cached body parts would otherwise dangle).
local function removeRocket(room)
	local existing = room.movableModel:FindFirstChild(ROCKET_MODEL)
	if existing then
		existing:Destroy()
	end
	RocketLauncher:clearRocketCache(room)
end
local RocketPlacer = {
	place = function(self, room)
		local spawnPoint = room.rocketSpawnPoint
		if not spawnPoint then
			return nil
		end
		local player = room:getOccupant()
		if not player then
			return nil
		end
		local folder = ReplicatedStorage:FindFirstChild(ROCKET_MODELS_FOLDER)
		if not folder then
			warn(`RocketPlacer: ReplicatedStorage/{ROCKET_MODELS_FOLDER} not found`)
			return nil
		end
		local count = #folder:GetChildren()
		if count == 0 then
			warn(`RocketPlacer: {ROCKET_MODELS_FOLDER} is empty`)
			return nil
		end
		local level = rocketLevelFor(PlayerProgressionService:getRebirths(player), count)
		local template = folder:FindFirstChild(`{ROCKET_PREFIX}{level}`)
		if not template or not template:IsA("Model") then
			warn(`RocketPlacer: {ROCKET_PREFIX}{level} missing or not a Model`)
			return nil
		end
		-- Clear the old rocket + the launcher caches that referenced it before swapping.
		removeRocket(room)
		local rocket = template:Clone()
		rocket.Name = ROCKET_MODEL
		-- Prepare the rocket for its at-rest state on the pad:
		--  - anchor every body part (some templates ship with unanchored parts that would
		--    otherwise fall; this is also the state the launcher expects — it unanchors on
		--    explode and re-anchors on reset),
		--  - turn the engine emitters OFF (templates author them inconsistently; the
		--    launcher lights them on launch and extinguishes them on every ending).
		for _, d in rocket:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif (d:IsA("Fire") or d:IsA("ParticleEmitter") or d:IsA("Smoke")) and d:FindFirstAncestor(NITRO_PART) ~= nil then
				d.Enabled = false
			end
		end
		rocket.Parent = room.movableModel
		-- Move the rocket's pivot exactly onto RocketSpawnPoint's position (orientation
		-- kept as authored). RocketSpawnPoint is the authoritative placement marker — if a
		-- template's pivot isn't at its base, part of the rocket may sit below the floor;
		-- that's an authoring detail to fix on the template, not something to compensate
		-- for here.
		local pivot = rocket:GetPivot()
		local _position = spawnPoint.Position
		local _position_1 = pivot.Position
		rocket:PivotTo(pivot + (_position - _position_1))
	end,
	clear = function(self, room)
		removeRocket(room)
	end,
}
return {
	RocketPlacer = RocketPlacer,
}
