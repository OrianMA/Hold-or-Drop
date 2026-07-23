-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local GroupService = _services.GroupService
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local _ShopBalance = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance")
local COMMUNITY = _ShopBalance.COMMUNITY
local MONEY_TIERS = _ShopBalance.MONEY_TIERS
local RESISTANCE_PASS = _ShopBalance.RESISTANCE_PASS
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _CheatConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig")
local ignoreGamePasses = _CheatConfig.ignoreGamePasses
local simulateGamePasses = _CheatConfig.simulateGamePasses
local simulatedOwnedPassIds = _CheatConfig.simulatedOwnedPassIds
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
-- HUD flash colours for the community-join feedback (see refreshCommunity).
local JOINED_COLOR = Color3.new(0.4, 1, 0.45)
local HINT_COLOR = Color3.new(0.6, 0.8, 1)
-- Owns detection of EXTERNAL boosts — Roblox group membership + game-pass ownership —
-- and writes the input attributes PlayerProgressionService folds into the money
-- multiplier / effective base cash.
--
-- Game-pass ownership is tracked as a per-player SET of owned pass ids:
--   • seeded once on join (real UserOwnsGamePassAsync, or the CheatConfig simulation);
--   • updated DIRECTLY from PromptGamePassPurchaseFinished using the purchased id.
-- We deliberately DO NOT re-query UserOwnsGamePassAsync after a purchase: that call
-- caches per session (and a Studio test purchase never grants real ownership), so a
-- re-query returns the pre-purchase value and the boost would never apply. Trusting
-- the event's id is correct in production AND testable in Studio.
local IN_COMMUNITY_ATTR = "InCommunity"
local MONEY_TIER_MULT_ATTR = "MoneyTierMult"
local HAS_RESISTANCE_PASS_ATTR = "HasResistancePass"
-- Per-player set of owned game-pass ids — the session source of truth.
local ownedPasses = {}
local function getOwned(player)
	local _player = player
	local set = ownedPasses[_player]
	if not set then
		set = {}
		local _player_1 = player
		local _set = set
		ownedPasses[_player_1] = _set
	end
	return set
end
-- Every real game-pass id the game cares about (id 0 = inert, skipped).
local function configuredPassIds()
	local ids = {}
	for _, tier in MONEY_TIERS do
		if tier.gamePassId > 0 then
			local _gamePassId = tier.gamePassId
			table.insert(ids, _gamePassId)
		end
	end
	if RESISTANCE_PASS.gamePassId > 0 then
		local _gamePassId = RESISTANCE_PASS.gamePassId
		table.insert(ids, _gamePassId)
	end
	return ids
end
local function realOwns(userId, gamePassId)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
	end)
	return ok and owns == true
end
-- Membership check. We use GetGroupsAsync (a web fetch) rather than
-- Player:IsInGroup because IsInGroup is cached for the whole session and would
-- never reflect a join made mid-session via the native PromptJoinAsync card —
-- GetGroupsAsync returns fresh data, so the ×2 can land the moment they join.
-- The scan runs inside the pcall so the array stays typed (the pcall result
-- itself collapses to unknown).
local function isInCommunity(player)
	local ok, member = pcall(function()
		local groups = GroupService:GetGroupsAsync(player.UserId)
		for _, group in groups do
			if group.Id == COMMUNITY.groupId then
				return true
			end
		end
		return false
	end)
	return ok and member == true
end
-- Re-derive the boost attributes from the player's owned-pass set (highest money
-- tier wins; resistance pass flat add), then fold them into the money multiplier.
local function recount(player)
	local set = getOwned(player)
	local tierMult = 1
	for _, tier in MONEY_TIERS do
		local _condition = tier.gamePassId > 0
		if _condition then
			local _gamePassId = tier.gamePassId
			_condition = set[_gamePassId] ~= nil
		end
		if _condition then
			tierMult = math.max(tierMult, tier.mult)
		end
	end
	player:SetAttribute(MONEY_TIER_MULT_ATTR, tierMult)
	local _player = player
	local _condition = RESISTANCE_PASS.gamePassId > 0
	if _condition then
		local _gamePassId = RESISTANCE_PASS.gamePassId
		_condition = set[_gamePassId] ~= nil
	end
	_player:SetAttribute(HAS_RESISTANCE_PASS_ATTR, _condition)
	PlayerProgressionService:recompute(player)
end
-- Synchronous defaults so the attributes exist immediately on join (before the
-- async resolve returns) — keeps deriveValues + the client readouts sane.
local function setDefaults(player)
	player:SetAttribute(IN_COMMUNITY_ATTR, false)
	player:SetAttribute(MONEY_TIER_MULT_ATTR, 1)
	player:SetAttribute(HAS_RESISTANCE_PASS_ATTR, false)
	PlayerProgressionService:recompute(player)
end
-- Full resolve — group membership + game-pass ownership. Yields (web calls); run
-- in task.spawn. Seeds the owned-pass set once for the session.
local function resolve(player)
	player:SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player))
	local set = getOwned(player)
	table.clear(set)
	if ignoreGamePasses then
		-- CHEAT — start like a player who never owned any game pass: seed nothing,
		-- so the set stays empty regardless of real Roblox ownership.
	elseif simulateGamePasses then
		-- TEST MODE — ignore real Roblox ownership, use the configured simulation.
		for _, id in simulatedOwnedPassIds do
			set[id] = true
		end
	else
		local userId = player.UserId
		for _, id in configuredPassIds() do
			if realOwns(userId, id) then
				set[id] = true
			end
		end
	end
	recount(player)
end
local BoostService
BoostService = {
	init = function(self)
		local onAdded = function(player)
			setDefaults(player)
			task.spawn(function()
				return resolve(player)
			end)
		end
		Players.PlayerAdded:Connect(onAdded)
		for _, player in Players:GetPlayers() do
			onAdded(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			-- ▼ Map.delete ▼
			local _valueExisted = ownedPasses[_player] ~= nil
			ownedPasses[_player] = nil
			-- ▲ Map.delete ▲
			return _valueExisted
		end)
		-- A successful purchase → record the purchased id DIRECTLY and recompute.
		-- The event is the only reliable "just bought" signal (see the file header on
		-- why we must NOT re-query UserOwnsGamePassAsync here).
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
			if not purchased then
				return nil
			end
			local _exp = getOwned(player)
			local _gamePassId = gamePassId
			_exp[_gamePassId] = true
			recount(player)
			-- Analytics: game-pass bought (counter, broken down by pass id).
			AnalyticsService:custom(player, "GamePassPurchased", gamePassId, tostring(gamePassId))
		end)
		-- The client opened the native community-join card (GroupService:PromptJoinAsync)
		-- and it returned Joined/AlreadyMember. Re-verify server-side and grant the ×2.
		Events.CommunityJoinedEvent.OnServerEvent:Connect(function(player)
			task.spawn(function()
				return BoostService:refreshCommunity(player)
			end)
		end)
	end,
	refreshCommunity = function(self, player)
		local wasIn = player:GetAttribute(IN_COMMUNITY_ATTR) == true
		local isIn = isInCommunity(player)
		player:SetAttribute(IN_COMMUNITY_ATTR, isIn)
		PlayerProgressionService:recompute(player)
		if isIn and not wasIn then
			-- Analytics: player just joined the community (grants ×2) — one-shot per join.
			AnalyticsService:custom(player, "CommunityJoined")
			Events.InformationTextEvent:FireClient(player, "Communauté rejointe — x2 argent !", JOINED_COLOR)
		elseif not isIn then
			Events.InformationTextEvent:FireClient(player, "Rejoins la communauté Grorian's Studio pour x2 argent !", HINT_COLOR)
		end
	end,
	devOwn = function(self, player, gamePassId)
		local _exp = getOwned(player)
		local _gamePassId = gamePassId
		_exp[_gamePassId] = true
		recount(player)
	end,
	devDisown = function(self, player, gamePassId)
		local _exp = getOwned(player)
		local _gamePassId = gamePassId
		_exp[_gamePassId] = nil
		recount(player)
	end,
	devReset = function(self, player)
		table.clear(getOwned(player))
		recount(player)
	end,
}
return {
	BoostService = BoostService,
}
