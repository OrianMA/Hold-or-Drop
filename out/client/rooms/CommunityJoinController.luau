-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local GroupService = _services.GroupService
local Players = _services.Players
local Workspace = _services.Workspace
local COMMUNITY = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance").COMMUNITY
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Per-player visibility + native join flow for the "join the community for ×2" prompts.
--
-- Every room folder has a CommunityJoinPart (a visible Part) holding a
-- ProximityPrompt + a BillboardGui, all globally Enabled in Studio (no per-player
-- server toggle). This controller narrows that down on each client, off two
-- replicated player attributes — exactly like RoomPromptController /
-- OwnerIndicatorController, and since client-side writes don't replicate, each
-- player only affects their own view:
--
--   • AssignedRoom — the P{n} folder this player owns. The CommunityJoinPart (the
--     part itself, its prompt and its billboard) is shown ONLY on the owned room;
--     every other room's part is made fully transparent and its prompt/billboard
--     disabled, so you only ever see the join cue at your own button.
--   • InCommunity  — true once the player is a member of the community group, so
--     the ×2 is already applied server-side (BoostService). On the owned room we
--     then DISABLE the prompt (nothing left to join) and flip the billboard text
--     to the "claimed" badge instead of hiding it.
--
-- StreamingEnabled is ON, so a room's CommunityJoinPart can stream IN at any time
-- (when the player gets near) and OUT again. We therefore (re)register per folder
-- on ChildAdded — not a one-shot FindFirstChild at boot — and re-apply visibility
-- each time a part appears, so a freshly streamed-in part is hidden immediately.
--
-- Joining: triggering the owned room's prompt opens Roblox's NATIVE community-join
-- card via GroupService:PromptJoinAsync (client-only). On a Joined/AlreadyMember
-- result we fire CommunityJoinedEvent so the server re-checks membership (fresh,
-- via GetGroupsAsync) and grants the ×2 — see BoostService.refreshCommunity.
local PLAYER_ZONES = "PlayerZones"
local COMMUNITY_JOIN_PART = "CommunityJoinPart"
local PROMPT_NAME = "ProximityPrompt"
local BILLBOARD_NAME = "BillboardGui"
local IN_COMMUNITY_ATTR = "InCommunity"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
-- Billboard text once the player is a member (reward already granted).
local CLAIMED_TEXT = "x2 réclamé"
local function init()
	local player = Players.LocalPlayer
	-- Keyed by room name so a part that streams out then back in (a fresh instance)
	-- simply replaces the stale entry.
	local entries = {}
	local applyEntry = function(entry)
		if entry.part.Parent == nil then
			return nil
		end
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		local member = player:GetAttribute(IN_COMMUNITY_ATTR) == true
		local own = entry.roomName == assigned
		-- Part: visible only on our own room — fully transparent on every other.
		entry.part.Transparency = if own then entry.defaultTransparency else 1
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
	local evaluate = function()
		for _, entry in entries do
			applyEntry(entry)
		end
	end
	-- Open Roblox's native community-join card, then tell the server to grant the
	-- ×2 if the player joined. Runs off the main thread (PromptJoinAsync yields).
	local promptJoin = function()
		-- Re-guard: only meaningful on our own room while not yet a member.
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		if assigned == "" then
			return nil
		end
		if player:GetAttribute(IN_COMMUNITY_ATTR) == true then
			return nil
		end
		task.spawn(function()
			local ok, status = pcall(function()
				return GroupService:PromptJoinAsync(COMMUNITY.groupId)
			end)
			if not ok then
				return nil
			end
			if status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
				Events.CommunityJoinedEvent:FireServer()
			end
		end)
	end
	-- Register (or refresh) a room's CommunityJoinPart and apply visibility now.
	-- Spawned because WaitForChild may yield while the prompt/billboard stream in.
	local registerPart = function(roomName, part)
		if not part:IsA("BasePart") then
			return nil
		end
		task.spawn(function()
			local promptInst = part:WaitForChild(PROMPT_NAME, 5)
			local billboardInst = part:WaitForChild(BILLBOARD_NAME, 5)
			local _result = promptInst
			if _result ~= nil then
				_result = _result:IsA("ProximityPrompt")
			end
			local prompt = if _result then promptInst else nil
			local _result_1 = billboardInst
			if _result_1 ~= nil then
				_result_1 = _result_1:IsA("BillboardGui")
			end
			local billboard = if _result_1 then billboardInst else nil
			local _label = billboard
			if _label ~= nil then
				_label = _label:FindFirstChildOfClass("TextLabel")
			end
			local label = _label
			local entry = {
				roomName = roomName,
				part = part,
				prompt = prompt,
				billboard = billboard,
				label = label,
				defaultText = if label then label.Text else "",
				defaultTransparency = part.Transparency,
			}
			local _roomName = roomName
			entries[_roomName] = entry
			applyEntry(entry)
			-- Triggering the prompt opens the native join card (client-only API).
			if prompt then
				prompt.Triggered:Connect(promptJoin)
			end
		end)
	end
	-- Watch one room folder: register the part if present, and again whenever one
	-- streams in (StreamingEnabled re-adds it as a fresh instance).
	local watchFolder = function(folder)
		local existing = folder:FindFirstChild(COMMUNITY_JOIN_PART)
		if existing then
			registerPart(folder.Name, existing)
		end
		folder.ChildAdded:Connect(function(child)
			if child.Name == COMMUNITY_JOIN_PART then
				registerPart(folder.Name, child)
			end
		end)
	end
	-- Server-driven — re-render whenever ownership or membership changes (e.g. the
	-- player joins the community via the card and the server grants the ×2).
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
		for _, folder in zones:GetChildren() do
			watchFolder(folder)
		end
		-- Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded:Connect(function(folder)
			return watchFolder(folder)
		end)
	end)
end
return {
	init = init,
}
