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
-- This controller (one per client) enables ONLY the local player's room prompt,
-- and only when they're not already in a session. Client-side writes to Enabled
-- don't replicate, so each player sees just their own prompt. The server still
-- validates ownership on Triggered, so this is purely visibility/UX.
local PLAYER_ZONES = "PlayerZones"
local BUTTON_MODEL = "ButtonModel"
local BUTTON_PART = "ButtonPart"
local PROMPT_NAME = "ProximityPrompt"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
local IN_SESSION_ATTR = "InSession"
local function init()
	local player = Players.LocalPlayer
	-- roomName ("P1") → its ProximityPrompt
	local prompts = {}
	local evaluate = function()
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		local inSession = player:GetAttribute(IN_SESSION_ATTR) == true
		for name, prompt in prompts do
			prompt.Enabled = name == assigned and not inSession
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
			local model = folder:WaitForChild(BUTTON_MODEL, 10)
			local _part = model
			if _part ~= nil then
				_part = _part:WaitForChild(BUTTON_PART, 10)
			end
			local part = _part
			local _prompt = part
			if _prompt ~= nil then
				_prompt = _prompt:WaitForChild(PROMPT_NAME, 10)
			end
			local prompt = _prompt
			local _result = prompt
			if _result ~= nil then
				_result = _result:IsA("ProximityPrompt")
			end
			if _result then
				local _name = folder.Name
				prompts[_name] = prompt
			else
				warn(`RoomPromptController: no ProximityPrompt under {folder.Name}`)
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
