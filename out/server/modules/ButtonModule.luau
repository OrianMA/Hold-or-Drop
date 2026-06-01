-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
-- Gameplay entry point for a single room's button. One instance per Room,
-- created at startup. The billboard / prompt text and the enabled state are
-- driven by the room itself (RoomService); this module only handles the trigger
-- and hands off to the in-game flow.
--
-- Access rule: a trigger is only honored when it comes from the room's current
-- occupant — every button is reachable on foot, so non-owners are ignored.
local ButtonModule
do
	ButtonModule = setmetatable({}, {
		__tostring = function()
			return "ButtonModule"
		end,
	})
	ButtonModule.__index = ButtonModule
	function ButtonModule.new(...)
		local self = setmetatable({}, ButtonModule)
		return self:constructor(...) or self
	end
	function ButtonModule:constructor(room)
		self.room = room
	end
	function ButtonModule:bind()
		self.room.proximityPrompt.Triggered:Connect(function(player)
			return self:onTriggered(player)
		end)
	end
	function ButtonModule:onTriggered(player)
		if not self.room:owns(player) then
			return nil
		end
		local character = player.Character
		if not character then
			return nil
		end
		ButtonSessionService:setSession(player, {
			room = self.room,
		})
		-- Hide the floating label-billboard for the active player only — restored
		-- when ButtonSessionService.cleanup() runs at the end of the session.
		if self.room.billboardGui then
			self.room.billboardGui.PlayerToHideFrom = player
		end
		Events.ButtonTriggerEvent:FireClient(player, self.room.cameraPosPart)
		self:teleportPlayer(character)
		self.room.proximityPrompt.Enabled = false
		UiService:Show(player, PopupType.ButtonMenu)
	end
	function ButtonModule:teleportPlayer(character)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return nil
		end
		local playerSize = character:GetExtentsSize().Y
		local _cFrame = self.room.playerPosPart.CFrame
		local _vector3 = Vector3.new(0, playerSize / 2, 0)
		hrp.CFrame = _cFrame + _vector3
		hrp.Anchored = true
	end
end
return {
	ButtonModule = ButtonModule,
}
