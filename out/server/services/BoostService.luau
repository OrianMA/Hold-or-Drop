-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local _ShopBalance = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance")
local COMMUNITY = _ShopBalance.COMMUNITY
local MONEY_TIERS = _ShopBalance.MONEY_TIERS
local SAFETY_PASS = _ShopBalance.SAFETY_PASS
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _CheatConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig")
local simulateGamePasses = _CheatConfig.simulateGamePasses
local simulatedOwnedPassIds = _CheatConfig.simulatedOwnedPassIds
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
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
local HAS_SAFETY_PASS_ATTR = "HasSafetyPass"
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
	if SAFETY_PASS.gamePassId > 0 then
		local _gamePassId = SAFETY_PASS.gamePassId
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
local function isInCommunity(player)
	local ok, result = pcall(function()
		return player:IsInGroup(COMMUNITY.groupId)
	end)
	return ok and result == true
end
-- Re-derive the boost attributes from the player's owned-pass set (highest money
-- tier wins; safety pass flat add), then fold them into the money multiplier.
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
	local _condition = SAFETY_PASS.gamePassId > 0
	if _condition then
		local _gamePassId = SAFETY_PASS.gamePassId
		_condition = set[_gamePassId] ~= nil
	end
	_player:SetAttribute(HAS_SAFETY_PASS_ATTR, _condition)
	PlayerProgressionService:recompute(player)
end
-- Synchronous defaults so the attributes exist immediately on join (before the
-- async resolve returns) — keeps deriveValues + the client readouts sane.
local function setDefaults(player)
	player:SetAttribute(IN_COMMUNITY_ATTR, false)
	player:SetAttribute(MONEY_TIER_MULT_ATTR, 1)
	player:SetAttribute(HAS_SAFETY_PASS_ATTR, false)
	PlayerProgressionService:recompute(player)
end
-- Full resolve — group membership + game-pass ownership. Yields (web calls); run
-- in task.spawn. Seeds the owned-pass set once for the session.
local function resolve(player)
	player:SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player))
	local set = getOwned(player)
	table.clear(set)
	if simulateGamePasses then
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
local BoostService = {
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
		end)
	end,
	refreshCommunity = function(self, player)
		local wasIn = player:GetAttribute(IN_COMMUNITY_ATTR) == true
		local isIn = isInCommunity(player)
		player:SetAttribute(IN_COMMUNITY_ATTR, isIn)
		PlayerProgressionService:recompute(player)
		if isIn and not wasIn then
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
