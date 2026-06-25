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
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
-- HUD flash colours for the community-join feedback (see refreshCommunity).
local JOINED_COLOR = Color3.new(0.4, 1, 0.45)
local HINT_COLOR = Color3.new(0.6, 0.8, 1)
-- Owns detection of EXTERNAL boosts — Roblox group membership + game-pass
-- ownership — and writes the input attributes PlayerProgressionService folds into
-- the money multiplier / effective base cash. Web calls (IsInGroup,
-- UserOwnsGamePassAsync) yield and can fail, so each is pcall-guarded. A game-pass
-- id of 0 is INERT (no web call, treated not-owned) until a real id is configured.
local IN_COMMUNITY_ATTR = "InCommunity"
local MONEY_TIER_MULT_ATTR = "MoneyTierMult"
local HAS_SAFETY_PASS_ATTR = "HasSafetyPass"
local function ownsGamePass(userId, gamePassId)
	if gamePassId <= 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
	end)
	return ok and owns == true
end
-- Highest owned money tier's multiplier (ladder — top tier wins). 1 if none.
-- Iterate high → low and return on the first owned tier: stops early and makes
-- at most one extra web call once an owned tier is found (id-0 tiers are skipped
-- by ownsGamePass without any web call).
local function resolveTierMult(userId)
	for i = #MONEY_TIERS - 1, 0, -1 do
		local tier = MONEY_TIERS[i + 1]
		if ownsGamePass(userId, tier.gamePassId) then
			return tier.mult
		end
	end
	return 1
end
local function isInCommunity(player)
	local ok, result = pcall(function()
		return player:IsInGroup(COMMUNITY.groupId)
	end)
	return ok and result == true
end
-- Synchronous defaults so the attributes exist immediately on join (before the
-- async web calls return) — keeps deriveValues + the client shop readout sane.
local function setDefaults(player)
	player:SetAttribute(IN_COMMUNITY_ATTR, false)
	player:SetAttribute(MONEY_TIER_MULT_ATTR, 1)
	player:SetAttribute(HAS_SAFETY_PASS_ATTR, false)
	PlayerProgressionService:recompute(player)
end
-- Full resolve — group + all game passes. Yields (web calls); run in task.spawn.
local function resolve(player)
	local userId = player.UserId
	player:SetAttribute(IN_COMMUNITY_ATTR, isInCommunity(player))
	player:SetAttribute(MONEY_TIER_MULT_ATTR, resolveTierMult(userId))
	player:SetAttribute(HAS_SAFETY_PASS_ATTR, ownsGamePass(userId, SAFETY_PASS.gamePassId))
	PlayerProgressionService:recompute(player)
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
		-- A successful game-pass purchase → re-resolve that player's ownership.
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _gamePassId, purchased)
			if purchased then
				task.spawn(function()
					return resolve(player)
				end)
			end
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
			Events.InformationTextEvent:FireClient(player, "Rejoins notre communauté Roblox pour x2 argent !", HINT_COLOR)
		end
	end,
}
return {
	BoostService = BoostService,
}
