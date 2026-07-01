-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- A Room wraps one Workspace/PlayerZones/P{n} folder and the ButtonModel it
-- contains. It resolves the model's parts once, tracks which player (if any)
-- currently owns the room, and drives the per-room UI (billboard + prompt text).
--
-- Ownership is the core access rule: only the assigned occupant may trigger the
-- room's button. Empty rooms have their ProximityPrompt disabled and show
-- "Empty" on the billboard.
local BUTTON_MODEL = "ButtonModel"
local BUTTON_PART = "ButtonPart"
local PLAYER_POS_PART = "PlayerPosPlaceHolder"
-- Camera parts live in the MovableModel (the rocket rig), not the ButtonModel:
-- CameraPosPart is the camera's start pose, CameraParentPart the orbit pivot the
-- camera always faces (see CameraController.StartOrbit).
local MOVABLE_MODEL = "MovableModel"
local CAMERA_POS_PART = "CameraPosPart"
local CAMERA_PIVOT_PART = "CameraParentPart"
-- The rocket rig carries its own ProximityPrompt (on RocketProximityPromptPart).
-- It triggers the exact same game flow as the button prompt (see ButtonModule) but
-- keeps its own fixed description instead of showing the cash gain.
local ROCKET_PROMPT_PART = "RocketProximityPromptPart"
local ROCKET_PROMPT_TEXT = "Launch the rocket"
-- Invisible marker the rocket is positioned onto (RocketPlacer seats the cloned
-- rocket here on assign — see RocketPlacer).
local ROCKET_SPAWN_POINT = "RocketSpawnPoint"
local UI_PART = "UiPart"
local BILLBOARD = "BillboardGui"
local GAIN_LABEL = "GainText"
local EMPTY_TEXT = "Empty"
local EMPTY_BASE_TEXT = "Empty base"
-- Accepted names for the per-room spawn marker (a plain Part, not a SpawnLocation).
-- Add yours here if you rename it.
local SPAWN_PART_NAMES = { "RespawnLocation", "SpawnLocation", "SpawnPart" }
-- Owner-display model — sibling of the ButtonModel inside the room folder.
-- Shows the occupant's name on a SurfaceGui and a "your base" BillboardGui that
-- is enabled client-side only for the owning player (see OwnerIndicatorController).
local OWNER_DISPLAY = "OwnerDisplay"
local NAME_PART = "NamePart"
local NAME_TEXT_LABEL = "NameText"
local OWNER_INDICATOR_PART = "OwnerIndicatorPart"
local Room
do
	Room = setmetatable({}, {
		__tostring = function()
			return "Room"
		end,
	})
	Room.__index = Room
	function Room.new(...)
		local self = setmetatable({}, Room)
		return self:constructor(...) or self
	end
	function Room:constructor(folder)
		self.valid = true
		self.name = folder.Name
		self.folder = folder
		local buttonModel = folder:FindFirstChild(BUTTON_MODEL)
		if not buttonModel or not buttonModel:IsA("Model") then
			self:invalidate(`missing {BUTTON_MODEL}`)
			return nil
		end
		self.buttonModel = buttonModel
		local buttonPart = buttonModel:FindFirstChild(BUTTON_PART)
		local _proximityPrompt = buttonPart
		if _proximityPrompt ~= nil then
			_proximityPrompt = _proximityPrompt:FindFirstChildOfClass("ProximityPrompt")
		end
		local proximityPrompt = _proximityPrompt
		local playerPosPart = buttonModel:FindFirstChild(PLAYER_POS_PART)
		if not buttonPart or not buttonPart:IsA("BasePart") or not proximityPrompt or not playerPosPart or not playerPosPart:IsA("BasePart") then
			self:invalidate("missing button parts")
			return nil
		end
		-- Camera parts (and the rocket's own ProximityPrompt) live in the
		-- MovableModel (rocket rig), not the ButtonModel.
		local movableModel = folder:FindFirstChild(MOVABLE_MODEL)
		local _cameraPosPart = movableModel
		if _cameraPosPart ~= nil then
			_cameraPosPart = _cameraPosPart:FindFirstChild(CAMERA_POS_PART)
		end
		local cameraPosPart = _cameraPosPart
		local _cameraPivotPart = movableModel
		if _cameraPivotPart ~= nil then
			_cameraPivotPart = _cameraPivotPart:FindFirstChild(CAMERA_PIVOT_PART)
		end
		local cameraPivotPart = _cameraPivotPart
		local _rocketProximityPrompt = movableModel
		if _rocketProximityPrompt ~= nil then
			_rocketProximityPrompt = _rocketProximityPrompt:FindFirstChild(ROCKET_PROMPT_PART)
			if _rocketProximityPrompt ~= nil then
				_rocketProximityPrompt = _rocketProximityPrompt:FindFirstChildOfClass("ProximityPrompt")
			end
		end
		local rocketProximityPrompt = _rocketProximityPrompt
		if not movableModel or not movableModel:IsA("Model") or not cameraPosPart or not cameraPosPart:IsA("BasePart") or not cameraPivotPart or not cameraPivotPart:IsA("BasePart") or not rocketProximityPrompt then
			self:invalidate(`missing {MOVABLE_MODEL} camera/prompt parts`)
			return nil
		end
		self.buttonPart = buttonPart
		self.proximityPrompt = proximityPrompt
		self.playerPosPart = playerPosPart
		self.movableModel = movableModel
		self.cameraPosPart = cameraPosPart
		self.cameraPivotPart = cameraPivotPart
		self.rocketProximityPrompt = rocketProximityPrompt
		-- ProximityPrompt.Enabled is a global property — there's no per-player
		-- toggle. We keep it disabled on the server and let each client enable only
		-- the prompt for the room they own (client-side writes don't replicate). See
		-- RoomPromptController. The server never flips Enabled again, so the client's
		-- local override is never stomped.
		self.proximityPrompt.Enabled = false
		-- The rocket prompt uses the exact same per-player visibility model, so it is
		-- also kept disabled on the server (RoomPromptController enables it for the
		-- owner). Unlike the button (which shows the cash gain via setGainCash), the
		-- rocket keeps its own fixed description.
		self.rocketProximityPrompt.Enabled = false
		self.rocketProximityPrompt.ObjectText = ROCKET_PROMPT_TEXT
		-- Rocket spawn marker (optional). RocketPlacer seats the cloned rocket
		-- onto it when the room is assigned.
		local spawnPoint = movableModel:FindFirstChild(ROCKET_SPAWN_POINT)
		local _result = spawnPoint
		if _result ~= nil then
			_result = _result:IsA("BasePart")
		end
		if _result then
			self.rocketSpawnPoint = spawnPoint
		else
			warn(`Room {self.name}: {MOVABLE_MODEL} missing {ROCKET_SPAWN_POINT} — no rocket will be placed`)
		end
		-- Billboard is optional — gameplay still works without it.
		local _billboard = buttonModel:FindFirstChild(UI_PART)
		if _billboard ~= nil then
			_billboard = _billboard:FindFirstChild(BILLBOARD)
		end
		local billboard = _billboard
		local _result_1 = billboard
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("BillboardGui")
		end
		if _result_1 then
			self.billboardGui = billboard
			local label = billboard:FindFirstChild(GAIN_LABEL, true)
			local _result_2 = label
			if _result_2 ~= nil then
				_result_2 = _result_2:IsA("TextLabel")
			end
			if _result_2 then
				self.gainLabel = label
			end
		end
		-- Optional spawn marker, placed anywhere in the room folder. Matched by name
		-- (any of SPAWN_PART_NAMES) so a regular Part works.
		for _, partName in SPAWN_PART_NAMES do
			local part = folder:FindFirstChild(partName, true)
			local _result_2 = part
			if _result_2 ~= nil then
				_result_2 = _result_2:IsA("BasePart")
			end
			if _result_2 then
				self.spawnPart = part
				break
			end
		end
		if not self.spawnPart then
			warn(`Room {self.name}: no spawn part ({table.concat(SPAWN_PART_NAMES, "/")}) — players won't spawn here`)
		end
		-- Optional owner-display model. We resolve the name label here, and disable
		-- the "your base" BillboardGui on the server so it stays hidden until each
		-- client locally enables it on their own room (OwnerIndicatorController).
		local ownerDisplay = folder:FindFirstChild(OWNER_DISPLAY)
		if ownerDisplay then
			local nameLabel = ownerDisplay:FindFirstChild(NAME_TEXT_LABEL, true)
			local _result_2 = nameLabel
			if _result_2 ~= nil then
				_result_2 = _result_2:IsA("TextLabel")
			end
			if _result_2 then
				self.ownerNameLabel = nameLabel
				self.ownerNameLabel.Text = EMPTY_BASE_TEXT
			else
				warn(`Room {self.name}: {OWNER_DISPLAY} missing TextLabel "{NAME_TEXT_LABEL}"`)
			end
			local indicatorPart = ownerDisplay:FindFirstChild(OWNER_INDICATOR_PART)
			local _billboard_1 = indicatorPart
			if _billboard_1 ~= nil then
				_billboard_1 = _billboard_1:FindFirstChildOfClass("BillboardGui")
			end
			local billboard = _billboard_1
			if billboard then
				billboard.Enabled = false
			end
		end
	end
	function Room:invalidate(reason)
		self.valid = false
		warn(`Room {self.name}: {reason} — room ignored`)
	end
	function Room:isValid()
		return self.valid
	end
	function Room:isEmpty()
		return self.occupant == nil
	end
	function Room:getOccupant()
		return self.occupant
	end
	function Room:owns(player)
		return self.occupant == player
	end
	function Room:assign(player)
		self.occupant = player
		if self.ownerNameLabel then
			self.ownerNameLabel.Text = `Base of {player.DisplayName}`
		end
	end
	function Room:release()
		self.occupant = nil
		self.proximityPrompt.ObjectText = EMPTY_TEXT
		if self.gainLabel then
			self.gainLabel.Text = EMPTY_TEXT
		end
		if self.ownerNameLabel then
			self.ownerNameLabel.Text = EMPTY_BASE_TEXT
		end
	end
	function Room:setGainCash(cash)
		-- Billboard label prefixed with '$' (gain cash is always positive).
		if self.gainLabel then
			self.gainLabel.Text = `${FormatCash(cash)}`
		end
		self.proximityPrompt.ObjectText = `{FormatCash(cash)} money`
	end
end
return {
	Room = Room,
}
