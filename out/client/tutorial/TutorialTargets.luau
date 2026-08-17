-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
-- Résout une cible de step en instance concrète.
--   "gui"   → chemin slash-séparé sous InGameUI, ex "ButtonMenu/StartButton"
--   "world" → une part du monde. StreamingEnabled est ACTIF : la découverte passe par
--             WaitForChild plutôt qu'un FindFirstChild one-shot (voir RoomPromptController).
local PLAYER_ZONES = "PlayerZones"
local BUTTON_MODEL = "ButtonModel"
local BUTTON_PART = "ButtonPart"
local SHOP = "Shop"
local SHOP_PROMPT_PART = "ProximityPromptPart"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
local TutorialTargets = {
	resolveGui = function(self, path)
		local root = TutorialUI:getInGameUI()
		if not root then
			return nil
		end
		local node = root
		for _, part in string.split(path, "/") do
			local _result = node
			if _result ~= nil then
				_result = _result:FindFirstChild(part)
			end
			node = _result
			if not node then
				return nil
			end
		end
		return if node:IsA("GuiObject") then node else nil
	end,
	resolveWorld = function(self, id)
		if id == "Shop" then
			local shop = Workspace:WaitForChild(SHOP, 10)
			local _part = shop
			if _part ~= nil then
				_part = _part:WaitForChild(SHOP_PROMPT_PART, 10)
			end
			local part = _part
			local _result = part
			if _result ~= nil then
				_result = _result:IsA("BasePart")
			end
			return if _result then part else nil
		end
		-- RoomButton — le bouton de la room ASSIGNÉE au joueur local.
		local _condition = (Players.LocalPlayer:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local roomName = _condition
		if roomName == "" then
			return nil
		end
		local zones = Workspace:WaitForChild(PLAYER_ZONES, 10)
		local _room = zones
		if _room ~= nil then
			_room = _room:WaitForChild(roomName, 10)
		end
		local room = _room
		local _model = room
		if _model ~= nil then
			_model = _model:WaitForChild(BUTTON_MODEL, 10)
		end
		local model = _model
		local _part = model
		if _part ~= nil then
			_part = _part:WaitForChild(BUTTON_PART, 10)
		end
		local part = _part
		local _result = part
		if _result ~= nil then
			_result = _result:IsA("BasePart")
		end
		return if _result then part else nil
	end,
}
return {
	TutorialTargets = TutorialTargets,
}
