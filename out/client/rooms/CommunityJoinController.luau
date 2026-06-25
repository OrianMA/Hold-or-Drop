-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
-- Per-player visibility for the "join the community for ×2" prompts.
--
-- Every room folder has a CommunityJoinPart holding a ProximityPrompt + a
-- BillboardGui, both globally Enabled in Studio (no per-player server toggle).
-- This controller narrows that down on each client, off two replicated player
-- attributes — exactly like RoomPromptController / OwnerIndicatorController, and
-- since client-side Enabled writes don't replicate, each player only affects
-- their own view:
--
--   • AssignedRoom — the P{n} folder this player owns. The CommunityJoinPart is
--     shown ONLY on the owned room; every other room's prompt + billboard are
--     disabled (no point nagging a player at someone else's button).
--   • InCommunity  — true once the player is a member of the community group, so
--     the ×2 is already applied server-side (BoostService). On the owned room we
--     then DISABLE the prompt (nothing left to join) and flip the billboard text
--     to the "claimed" badge instead of hiding it.
--
-- Roblox exposes no in-experience "join group/community" API, so the prompt can't
-- open a join dialog — it just re-checks membership server-side (RoomService →
-- BoostService.refreshCommunity) and the player joins via Roblox's own UI.
local PLAYER_ZONES = "PlayerZones"
local COMMUNITY_JOIN_PART = "CommunityJoinPart"
local IN_COMMUNITY_ATTR = "InCommunity"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
-- Billboard text once the player is a member (reward already granted).
local CLAIMED_TEXT = "x2 réclamé"
local function init()
	local player = Players.LocalPlayer
	local entries = {}
	local evaluate = function()
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		local member = player:GetAttribute(IN_COMMUNITY_ATTR) == true
		for _, entry in entries do
			local own = entry.roomName == assigned
			-- Prompt: only on our own room, and only while we still need to join.
			if entry.prompt then
				entry.prompt.Enabled = own and not member
			end
			-- Billboard: only on our own room — hidden on every other room.
			if entry.billboard then
				entry.billboard.Enabled = own
			end
			-- Text: claimed badge once we're a member, else the authored CTA.
			if entry.label then
				entry.label.Text = if member then CLAIMED_TEXT else entry.defaultText
			end
		end
	end
	-- Server-driven — re-render whenever ownership or membership changes (e.g. the
	-- player joins the group then triggers the prompt and the server re-checks).
	player:GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR):Connect(evaluate)
	player:GetAttributeChangedSignal(IN_COMMUNITY_ATTR):Connect(evaluate)
	-- Discovery runs off the main thread (WaitForChild may yield while the zones
	-- stream/replicate in).
	task.spawn(function()
		local zones = Workspace:WaitForChild(PLAYER_ZONES, 30)
		if not zones then
			warn("CommunityJoinController: Workspace/PlayerZones not found")
			return nil
		end
		local register = function(folder)
			local part = folder:FindFirstChild(COMMUNITY_JOIN_PART)
			if not part then
				return nil
			end
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			local billboard = part:FindFirstChildOfClass("BillboardGui")
			local _label = billboard
			if _label ~= nil then
				_label = _label:FindFirstChildOfClass("TextLabel")
			end
			local label = _label
			local _arg0 = {
				roomName = folder.Name,
				prompt = prompt,
				billboard = billboard,
				label = label,
				defaultText = if label then label.Text else "",
			}
			table.insert(entries, _arg0)
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
