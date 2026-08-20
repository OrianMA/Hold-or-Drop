-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _DailyRewardConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "DailyRewardConfig")
local DAILY_AUTO_OPEN_ATTR = _DailyRewardConfig.DAILY_AUTO_OPEN_ATTR
local DAILY_CLAIMED_ATTR = _DailyRewardConfig.DAILY_CLAIMED_ATTR
local DAILY_MULTIPLIER_ATTR = _DailyRewardConfig.DAILY_MULTIPLIER_ATTR
local DAILY_X3_MULTIPLIER = _DailyRewardConfig.DAILY_X3_MULTIPLIER
local dailyMultiplier = _DailyRewardConfig.dailyMultiplier
local dayIndex = _DailyRewardConfig.dayIndex
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local _AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService")
local AnalyticsService = _AnalyticsService.AnalyticsService
local TxType = _AnalyticsService.TxType
local TutorialService = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialService").TutorialService
local dailyRewardCheatKey = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").dailyRewardCheatKey
-- Authoritative daily reward. Coming back N days in a row pays
-- `EffectiveBaseCash × N` — the Robux "3X Claim" product triples that total.
--
-- State lives in PlayerDataService (same store, no migration — the two keys default
-- to 0 for existing saves, exactly like Playtime did):
--   DailyStreak    — consecutive days already CLAIMED (0 = never)
--   DailyLastClaim — UTC day index of the last claim (0 = never)
--
-- From those two the service derives and publishes two replicated attributes the
-- client reads directly, so the popup needs no round-trip to render:
--   DailyMultiplier — what a claim would apply right now
--   DailyClaimed    — today's reward already taken
--   DailyAutoOpen   — the popup must show itself (see the auto-open rules below)
--
-- The client is never trusted: it only asks (DailyRewardClaimEvent), the streak and
-- the day boundary are re-derived here on every grant.
local STREAK_KEY = "DailyStreak"
local LAST_CLAIM_KEY = "DailyLastClaim"
-- PlayerDataService writes its attributes after an async DataStore load; give it a
-- bounded window rather than reading a nil attribute as "never claimed" (which would
-- hand out a second reward and reset the streak).
local LOAD_TIMEOUT = 30
local LOAD_POLL = 0.1
-- Auto-open rules — the gate is the TUTORIAL, not the account age:
--   • tutorial running (a brand-new player, a resumed tutorial, or the forceTutorial
--     cheat): the popup is DEFERRED to the first rebirth AFTER the tutorial ends. It
--     must never land on top of the onboarding, whatever put the player there;
--   • anybody else joining with a pending reward: the popup opens right away.
-- Deferred players sit in this set until they rebirth (tutorial over) or leave.
local deferredToRebirth = {}
-- TutorialService publishes this attribute at the end of its own async load — before
-- that, isActive() would answer "false" simply because the state isn't in yet, and the
-- popup would race the tutorial it is supposed to avoid.
local TUTORIAL_STEP_ATTR = "TutorialStep"
-- The streak a claim would commit right now: +1 when the last claim was yesterday,
-- back to 1 otherwise (a missed day breaks the chain). Already claimed today → the
-- stored streak, unchanged.
local function pendingStreak(player)
	local streak = PlayerDataService:get(player, STREAK_KEY)
	local last = PlayerDataService:get(player, LAST_CLAIM_KEY)
	local today = dayIndex(os.time())
	if last == today then
		return math.max(1, streak)
	end
	if last == today - 1 then
		return streak + 1
	end
	return 1
end
local function hasClaimedToday(player)
	return PlayerDataService:get(player, LAST_CLAIM_KEY) == dayIndex(os.time())
end
-- Re-derives the two published attributes from the stored state. Called on join, on
-- every grant, and whenever the popup state could have gone stale.
local function publish(player)
	player:SetAttribute(DAILY_MULTIPLIER_ATTR, dailyMultiplier(pendingStreak(player)))
	player:SetAttribute(DAILY_CLAIMED_ATTR, hasClaimedToday(player))
end
-- Demande au client d'ouvrir le popup : on incrémente le compteur, il ouvre dès qu'il
-- voit une valeur plus haute que la dernière traitée (voir DAILY_AUTO_OPEN_ATTR).
local function requestOpen(player)
	local _condition = (player:GetAttribute(DAILY_AUTO_OPEN_ATTR))
	if _condition == nil then
		_condition = 0
	end
	local current = _condition
	player:SetAttribute(DAILY_AUTO_OPEN_ATTR, current + 1)
end
-- Ouverture à la CONNEXION : seulement si la récompense du jour est encore à prendre.
-- Le cheat (§9) est la seule dérogation, et il ne vaut QUE pour cette porte d'entrée —
-- le rebirth, lui, teste `hasClaimedToday` sans exemption (voir onRebirth).
local function shouldOpenOnJoin(player)
	return not hasClaimedToday(player) or dailyRewardCheatKey
end
-- Credits the cash and reports it. `multiplier` is the streak multiplier, `bonus` the
-- product factor (1 or 3) — kept apart so the client can show which one paid.
local function payout(player, multiplier, bonus)
	local baseCash = PlayerProgressionService:get(player, "EffectiveBaseCash")
	local amount = math.floor(baseCash * multiplier * bonus)
	if amount <= 0 then
		return 0
	end
	PlayerDataService:add(player, "Money", amount)
	-- Analytics: a faucet — cash entering the economy. Robux-paid claims are tagged
	-- IAP so the free and the ×3 paths stay separable on the dashboard.
	AnalyticsService:cashSource(player, amount, PlayerDataService:get(player, "Money"), if bonus > 1 then TxType.IAP else TxType.Gameplay, `DailyReward_x{multiplier}`)
	AnalyticsService:custom(player, if bonus > 1 then "DailyRewardClaimedX3" else "DailyRewardClaimed", multiplier)
	Events.DailyRewardGrantedEvent:FireClient(player, amount, multiplier, bonus)
	return amount
end
-- Commits today's claim: stores the new streak + today's day index.
local function commit(player, streak)
	PlayerDataService:set(player, STREAK_KEY, streak)
	PlayerDataService:set(player, LAST_CLAIM_KEY, dayIndex(os.time()))
	local _player = player
	deferredToRebirth[_player] = nil
end
local function handleClaim(player)
	if hasClaimedToday(player) then
		return nil
	end
	local streak = pendingStreak(player)
	local multiplier = dailyMultiplier(streak)
	commit(player, streak)
	publish(player)
	payout(player, multiplier, 1)
end
local DailyRewardService
DailyRewardService = {
	init = function(self)
		local onAdded = function(player)
			player:SetAttribute(DAILY_AUTO_OPEN_ATTR, 0)
			task.spawn(function()
				if not DailyRewardService:waitForData(player) then
					return nil
				end
				publish(player)
				if not shouldOpenOnJoin(player) then
					return nil
				end
				-- The tutorial owns the screen — wait for the first rebirth after it ends.
				if TutorialService:isActive(player) then
					local _player = player
					deferredToRebirth[_player] = true
				else
					requestOpen(player)
				end
			end)
		end
		Players.PlayerAdded:Connect(onAdded)
		for _, player in Players:GetPlayers() do
			onAdded(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			-- ▼ Set.delete ▼
			local _valueExisted = deferredToRebirth[_player] ~= nil
			deferredToRebirth[_player] = nil
			-- ▲ Set.delete ▲
			return _valueExisted
		end)
		Events.DailyRewardClaimEvent.OnServerEvent:Connect(function(player)
			return handleClaim(player)
		end)
		-- CHEAT — inerte en production : sans le flag serveur, l'event est ignoré même
		-- si un client le tire.
		if dailyRewardCheatKey then
			Events.DailyRewardCheatEvent.OnServerEvent:Connect(function(player)
				return DailyRewardService:devAdvanceDay(player)
			end)
		end
	end,
	waitForData = function(self, player)
		local deadline = os.clock() + LOAD_TIMEOUT
		while player:GetAttribute(LAST_CLAIM_KEY) == nil or player:GetAttribute(TUTORIAL_STEP_ATTR) == nil do
			if player.Parent == nil then
				return false
			end
			if os.clock() > deadline then
				warn(`DailyRewardService: player/tutorial data never loaded for {player.Name}`)
				return false
			end
			task.wait(LOAD_POLL)
		end
		return true
	end,
	claimPaid = function(self, player)
		local streak = pendingStreak(player)
		local multiplier = dailyMultiplier(streak)
		if not hasClaimedToday(player) then
			commit(player, streak)
			publish(player)
		end
		payout(player, multiplier, DAILY_X3_MULTIPLIER)
	end,
	onRebirth = function(self, player)
		local _player = player
		if not (deferredToRebirth[_player] ~= nil) then
			return nil
		end
		if TutorialService:isActive(player) then
			return nil
		end
		local _player_1 = player
		deferredToRebirth[_player_1] = nil
		if not hasClaimedToday(player) then
			requestOpen(player)
		end
	end,
	isPending = function(self, player)
		return not hasClaimedToday(player)
	end,
	devSetStreak = function(self, player, streak, daysAgo)
		PlayerDataService:set(player, STREAK_KEY, math.max(0, math.floor(streak)))
		PlayerDataService:set(player, LAST_CLAIM_KEY, dayIndex(os.time()) - math.max(0, math.floor(daysAgo)))
		publish(player)
		if not hasClaimedToday(player) then
			requestOpen(player)
		end
	end,
	devAdvanceDay = function(self, player)
		local today = dayIndex(os.time())
		local last = PlayerDataService:get(player, LAST_CLAIM_KEY)
		PlayerDataService:set(player, LAST_CLAIM_KEY, (if last > 0 then last else today) - 1)
		publish(player)
		requestOpen(player)
	end,
	devReset = function(self, player)
		PlayerDataService:set(player, STREAK_KEY, 0)
		PlayerDataService:set(player, LAST_CLAIM_KEY, 0)
		publish(player)
		requestOpen(player)
	end,
}
return {
	DailyRewardService = DailyRewardService,
}
