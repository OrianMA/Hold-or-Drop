-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
-- Per-player ProximityPrompt visibility.
--
-- ProximityPrompt.Enabled is a global property, so the server can't show a prompt
-- to one player only. Instead the server keeps every room's prompt disabled and
-- publishes two attributes on each player:
--   • AssignedRoom — the P{n} folder name this player owns ("" when none)
--   • InSession    — true while the player is mid-button-game
--
-- This controller (one per client) enables ONLY the local player's room prompts
-- — the button prompt AND the rocket prompt, which both trigger the same game —
-- and only when they're not already in a session. Client-side writes to Enabled
-- don't replicate, so each player sees just their own prompts. The server still
-- validates ownership on Triggered, so this is purely visibility/UX.
local PLAYER_ZONES = "PlayerZones"
local BUTTON_MODEL = "ButtonModel"
local BUTTON_PART = "ButtonPart"
-- The rocket prompt lives on MovableModel/RocketProximityPromptPart (same prompt
-- name) and is shown/hidden together with the button prompt.
local MOVABLE_MODEL = "MovableModel"
local ROCKET_PROMPT_PART = "RocketProximityPromptPart"
local PROMPT_NAME = "ProximityPrompt"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
local IN_SESSION_ATTR = "InSession"
local function init()
	local player = Players.LocalPlayer
	-- roomName ("P1") → its prompts (button + rocket), shown/hidden together
	local prompts = {}
	local evaluate = function()
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		local inSession = player:GetAttribute(IN_SESSION_ATTR) == true
		for name, list in prompts do
			local enabled = name == assigned and not inSession
			for _, prompt in list do
				prompt.Enabled = enabled
			end
		end
	end
	-- Server-driven state — re-render whenever ownership or session state changes.
	player:GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR):Connect(evaluate)
	player:GetAttributeChangedSignal(IN_SESSION_ATTR):Connect(evaluate)
	-- Discovery runs off the main thread (WaitForChild may yield while the zones
	-- stream/replicate in).
	task.spawn(function()
		local zones = Workspace:WaitForChild(PLAYER_ZONES, 30)
		if not zones then
			warn("RoomPromptController: Workspace/PlayerZones not found")
			return nil
		end
		local register = function(folder)
			local list = {}
			-- Button prompt — ButtonModel/ButtonPart/ProximityPrompt
			local buttonModel = folder:WaitForChild(BUTTON_MODEL, 10)
			local _buttonPart = buttonModel
			if _buttonPart ~= nil then
				_buttonPart = _buttonPart:WaitForChild(BUTTON_PART, 10)
			end
			local buttonPart = _buttonPart
			local _buttonPrompt = buttonPart
			if _buttonPrompt ~= nil then
				_buttonPrompt = _buttonPrompt:WaitForChild(PROMPT_NAME, 10)
			end
			local buttonPrompt = _buttonPrompt
			local _result = buttonPrompt
			if _result ~= nil then
				_result = _result:IsA("ProximityPrompt")
			end
			if _result then
				table.insert(list, buttonPrompt)
			else
				warn(`RoomPromptController: no button ProximityPrompt under {folder.Name}`)
			end
			-- Rocket prompt — MovableModel/RocketProximityPromptPart/ProximityPrompt
			local movableModel = folder:WaitForChild(MOVABLE_MODEL, 10)
			local _rocketPart = movableModel
			if _rocketPart ~= nil then
				_rocketPart = _rocketPart:WaitForChild(ROCKET_PROMPT_PART, 10)
			end
			local rocketPart = _rocketPart
			local _rocketPrompt = rocketPart
			if _rocketPrompt ~= nil then
				_rocketPrompt = _rocketPrompt:WaitForChild(PROMPT_NAME, 10)
			end
			local rocketPrompt = _rocketPrompt
			local _result_1 = rocketPrompt
			if _result_1 ~= nil then
				_result_1 = _result_1:IsA("ProximityPrompt")
			end
			if _result_1 then
				table.insert(list, rocketPrompt)
			else
				warn(`RoomPromptController: no rocket ProximityPrompt under {folder.Name}`)
			end
			if #list > 0 then
				local _name = folder.Name
				prompts[_name] = list
			end
		end
		for _, folder in zones:GetChildren() do
			register(folder)
		end
		evaluate()
		-- Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded:Connect(function(folder)
			return task.spawn(function()
				register(folder)
				evaluate()
			end)
		end)
	end)
end
return {
	init = init,
}
