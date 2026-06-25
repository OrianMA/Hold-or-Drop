-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
-- Per-player visibility for the "join the community for ×2" prompts.
--
-- Every room folder has a CommunityJoinPart holding a ProximityPrompt + a
-- BillboardGui, both globally Enabled in Studio (so every player sees them by
-- default). Once a player is a member of the community group, the ×2 money boost is
-- already applied server-side (BoostService → InCommunity attribute) and there's no
-- reason to keep nagging them — so this controller hides BOTH the prompt and the
-- billboard for members.
--
-- InCommunity is resolved server-side and replicates as a player attribute: at join
-- (BoostService.resolve, so an already-member is handled on spawn) and again when the
-- player triggers the prompt (RoomService → BoostService.refreshCommunity). This
-- controller just mirrors it. Enabled is a global property and client-side writes
-- don't replicate (same trick as RoomPromptController), so hiding here only affects
-- the local member — non-members still see the prompts.
local PLAYER_ZONES = "PlayerZones"
local COMMUNITY_JOIN_PART = "CommunityJoinPart"
local IN_COMMUNITY_ATTR = "InCommunity"
local function init()
	local player = Players.LocalPlayer
	local prompts = {}
	local billboards = {}
	local evaluate = function()
		local member = player:GetAttribute(IN_COMMUNITY_ATTR) == true
		for _, prompt in prompts do
			prompt.Enabled = not member
		end
		for _, billboard in billboards do
			billboard.Enabled = not member
		end
	end
	-- Server-driven — re-render whenever membership changes (e.g. the player joins
	-- the group then triggers the prompt and the server re-checks).
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
			if prompt then
				table.insert(prompts, prompt)
			end
			if billboard then
				table.insert(billboards, billboard)
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
