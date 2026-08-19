-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local _AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService")
local AnalyticsService = _AnalyticsService.AnalyticsService
local TxType = _AnalyticsService.TxType
-- EndGameButton gameplay state — entered when the player releases the button
-- (success / grace-period cancel) or when the player dies from the explosion.
-- Coordinates the transition into the ButtonFinishGame popup.
local RELEASE_DELAY = 1
local POST_RESPAWN_DELAY = 0.3
-- Credited to the player once the client signals the end of the last tween
-- (EndGameFinishedEvent). One pending entry per player at most.
--
-- `aborted` is set by flush() when another popup opened: the finish popup is then never
-- shown (or its animation is cut short client-side), but the entry stays until the client
-- confirms the replacement floating text landed — the credit path is the same either way.
-- `clientOwes` means the client was told to show something and WILL send back an
-- EndGameFinishedEvent — see staleSignals.
local pending = {}
-- A flushed payout's floating text lives ~1.5 s. If the player squeezes a whole new run
-- into that window, its enter() banks the old entry early and the text's late signal
-- would land on the NEW payout — crediting it before its animation even runs, which
-- leaves the HUD showing double until the next gain. Count those owed-but-obsolete
-- signals here and swallow them instead.
local staleSignals = {}
-- Bank whatever is queued for this player and clear the entry. No-op when nothing is
-- pending, so it's safe to call defensively. `superseded` marks the case above: a new
-- run replacing an entry whose client visual is still on screen.
local function creditPending(player, superseded)
	if superseded == nil then
		superseded = false
	end
	local _player = player
	local entry = pending[_player]
	if not entry then
		return nil
	end
	local _player_1 = player
	pending[_player_1] = nil
	if entry.earned > 0 then
		PlayerDataService:add(player, "Money", entry.earned)
		-- Cash faucet: log the gameplay Source with the resulting balance (win / loss reward).
		AnalyticsService:cashSource(player, entry.earned, PlayerDataService:get(player, "Money"), TxType.Gameplay, entry.itemSku)
	end
	if superseded and entry.clientOwes then
		local _exp = player
		local _player_2 = player
		local _condition = staleSignals[_player_2]
		if _condition == nil then
			_condition = 0
		end
		staleSignals[_exp] = _condition + 1
	end
end
local function waitForRespawn(player)
	local character = player.Character
	local _humanoid = character
	if _humanoid ~= nil then
		_humanoid = _humanoid:FindFirstChildOfClass("Humanoid")
	end
	local humanoid = _humanoid
	local alive = character ~= nil and humanoid ~= nil and humanoid.Health > 0
	if alive then
		return nil
	end
	player.CharacterAdded:Wait()
	task.wait(POST_RESPAWN_DELAY)
end
local EndGameButtonModule
EndGameButtonModule = {
	enter = function(self, player, mode, baseCash, multiplier, earned, lossMultiplier, claimBonus)
		ButtonSessionService:cleanup(player)
		UiService:HideCurrent(player)
		-- A flushed payout from the previous run may still be waiting for its client
		-- signal (the player can start and finish a new run in the meantime) — bank it
		-- now instead of losing it when we overwrite the entry.
		creditPending(player, true)
		local entry = {
			earned = earned,
			aborted = false,
			clientOwes = false,
			itemSku = "ClaimWin",
		}
		local _player = player
		pending[_player] = entry
		task.spawn(function()
			if mode == "released" then
				task.wait(RELEASE_DELAY)
			else
				waitForRespawn(player)
			end
			-- Player may have disconnected while we were waiting
			if player.Parent == nil then
				local _player_1 = player
				if pending[_player_1] == entry then
					local _player_2 = player
					pending[_player_2] = nil
				end
				return nil
			end
			-- A popup opened (or a rebirth landed) while we waited → the finish screen is
			-- off the table. flush() already sent the replacement floating text.
			local _condition = entry.aborted
			if not _condition then
				local _player_1 = player
				_condition = pending[_player_1] ~= entry
			end
			if _condition then
				return nil
			end
			entry.clientOwes = true
			UiService:Show(player, PopupType.ButtonFinishGame)
			Events.EndGameStartEvent:FireClient(player, baseCash, multiplier, lossMultiplier, claimBonus)
		end)
	end,
	flush = function(self, player)
		local _player = player
		local entry = pending[_player]
		if not entry or entry.aborted then
			return nil
		end
		entry.aborted = true
		-- Nothing was won → just drop the finish screen, no floating text.
		if entry.earned <= 0 then
			local _player_1 = player
			pending[_player_1] = nil
			return nil
		end
		entry.clientOwes = true
		Events.EndGamePayoutFlushEvent:FireClient(player, entry.earned)
	end,
	enterRewardOnly = function(self, player, reward)
		ButtonSessionService:cleanup(player)
		UiService:HideCurrent(player)
		creditPending(player, true)
		local _player = player
		local _arg1 = {
			earned = reward,
			aborted = false,
			clientOwes = true,
			itemSku = "LossConsolation",
		}
		pending[_player] = _arg1
		Events.LossRewardEvent:FireClient(player, reward)
	end,
	cancelPending = function(self, player)
		-- Mark before dropping so a still-waiting enter() task bails instead of opening
		-- the popup on a balance that was just reset to 0.
		local _player = player
		local entry = pending[_player]
		if entry then
			entry.aborted = true
		end
		local _player_1 = player
		pending[_player_1] = nil
		local _player_2 = player
		staleSignals[_player_2] = nil
		UiService:Hide(player, PopupType.ButtonFinishGame)
	end,
	init = function(self)
		-- Any other popup opening converts a pending payout into a floating text.
		UiService:SetBeforeShow(function(player)
			return EndGameButtonModule:flush(player)
		end)
		Events.EndGameFinishedEvent.OnServerEvent:Connect(function(player)
			-- Late signal from a payout already banked by the next run — drop it so it
			-- doesn't credit (and close) the payout that replaced it.
			local _player = player
			local _condition = staleSignals[_player]
			if _condition == nil then
				_condition = 0
			end
			local stale = _condition
			if stale > 0 then
				local _player_1 = player
				local _arg1 = stale - 1
				staleSignals[_player_1] = _arg1
				return nil
			end
			creditPending(player)
			UiService:Hide(player, PopupType.ButtonFinishGame)
		end)
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			pending[_player] = nil
			local _player_1 = player
			staleSignals[_player_1] = nil
		end)
	end,
}
return {
	EndGameButtonModule = EndGameButtonModule,
}
