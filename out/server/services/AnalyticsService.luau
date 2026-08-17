-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local RobloxAnalytics = _services.AnalyticsService
local HttpService = _services.HttpService
local Players = _services.Players
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
-- Thin, crash-proof wrapper around Roblox's official AnalyticsService (Creator Hub →
-- Analytics). NOTHING here needs any Studio setup — the events flow to the dashboard
-- automatically for a published experience (first data lands after ~24h).
--
-- Design rules:
--   • Every Roblox analytics call is wrapped in pcall — analytics can throttle or be
--     disabled, and it must NEVER break gameplay. A failed log is silently dropped.
--   • Server-only. Gameplay is server-authoritative, so every economy/progression
--     event is logged from the server at the exact point state truly changes.
--   • Semantic helpers (cashSource/cashSink/runStep/…) so call sites stay one-liners.
--
-- Event map:
--   Economy  → cash earned (Source) / spent (Sink): gameplay payouts, shop, rebirth, IAP.
--   Funnel   "CoreRun"  → per-run progress: Launch → Claim → Banked (repeatable).
--   Onboarding funnel   → first-session only: Joined → Launch → Claim → Purchase → Rebirth.
--   Progression "Rebirth" → each rebirth completed (level = rebirth count).
--   Custom   → per-event counters with a breakdown field (RocketLaunched, RunLost, …).
local CURRENCY = "Cash"
-- Recommended transactionType buckets (free strings on the API; kept consistent here).
local TxType = {
	Gameplay = "Gameplay",
	Shop = "Shop",
	Rebirth = "Rebirth",
	IAP = "IAP",
}
-- The 3 custom-field slots the dashboard exposes for breakdowns.
local FIELD_KEYS = { Enum.AnalyticsCustomFieldKeys.CustomField01.Name, Enum.AnalyticsCustomFieldKeys.CustomField02.Name, Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
-- Builds the customFields object (or undefined) from up to 3 positional values.
local function buildFields(...)
	local values = { ... }
	local fields = {}
	local any = false
	do
		local i = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < #values and i < #FIELD_KEYS) then
				break
			end
			local v = values[i + 1]
			if v ~= nil then
				fields[FIELD_KEYS[i + 1]] = v
				any = true
			end
		end
	end
	return if any then fields else nil
end
-- Onboarding steps already sent this session (per player) — a step is logged at most once.
local onboardingSent = {}
-- One funnel step, whatever the funnel. pcall'd: throttled analytics must never break
-- gameplay.
local function logFunnelStep(player, funnelName, sessionId, step, stepName)
	pcall(function()
		return RobloxAnalytics:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
	end)
end
local AnalyticsService
AnalyticsService = {
	init = function(self)
		local onJoin = function(player)
			task.spawn(function()
				-- Wait until progression finished loading (it sets Rebirths at the end of
				-- the async load), so isFirstSession is decided before the join step.
				if player:GetAttribute("Rebirths") == nil then
					player:GetAttributeChangedSignal("Rebirths"):Wait()
				end
				AnalyticsService:onboardingStep(player, 1, "Joined")
			end)
		end
		Players.PlayerAdded:Connect(onJoin)
		for _, player in Players:GetPlayers() do
			onJoin(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			-- ▼ Map.delete ▼
			local _valueExisted = onboardingSent[_player] ~= nil
			onboardingSent[_player] = nil
			-- ▲ Map.delete ▲
			return _valueExisted
		end)
	end,
	newRunId = function(self)
		local ok, id = pcall(function()
			return HttpService:GenerateGUID(false)
		end)
		return if ok then id else `{tick()}`
	end,
	funnelStep = function(self, player, funnelName, sessionId, step, stepName)
		logFunnelStep(player, funnelName, sessionId, step, stepName)
	end,
	runStep = function(self, player, runId, step, stepName)
		logFunnelStep(player, "CoreRun", runId, step, stepName)
	end,
	onboardingStep = function(self, player, step, stepName)
		if not PlayerProgressionService:isFirstSession(player) then
			return nil
		end
		local _player = player
		local sent = onboardingSent[_player]
		if not sent then
			sent = {}
			local _player_1 = player
			local _sent = sent
			onboardingSent[_player_1] = _sent
		end
		local _sent = sent
		local _step = step
		if _sent[_step] ~= nil then
			return nil
		end
		local _sent_1 = sent
		local _step_1 = step
		_sent_1[_step_1] = true
		pcall(function()
			return RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, stepName)
		end)
	end,
	cashSource = function(self, player, amount, endingBalance, transactionType, itemSku)
		if amount <= 0 then
			return nil
		end
		pcall(function()
			return RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, CURRENCY, amount, endingBalance, transactionType, itemSku)
		end)
	end,
	cashSink = function(self, player, amount, endingBalance, transactionType, itemSku)
		if amount <= 0 then
			return nil
		end
		pcall(function()
			return RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, CURRENCY, amount, endingBalance, transactionType, itemSku)
		end)
	end,
	rebirth = function(self, player, rebirths)
		pcall(function()
			return RobloxAnalytics:LogProgressionEvent(player, "Rebirth", Enum.AnalyticsProgressionType.Complete, rebirths, `Rebirth {rebirths}`)
		end)
	end,
	custom = function(self, player, eventName, value, field)
		pcall(function()
			return RobloxAnalytics:LogCustomEvent(player, eventName, value, (buildFields(field)))
		end)
	end,
}
return {
	TxType = TxType,
	AnalyticsService = AnalyticsService,
}
