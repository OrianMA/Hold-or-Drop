-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
-- EndGameButton gameplay state — entered when the player releases the button
-- (success / parry / grace-period cancel) or when the player dies from the
-- explosion. Coordinates the transition into the ButtonFinishGame popup.
local RELEASE_DELAY = 1
local POST_RESPAWN_DELAY = 0.3
-- Credited to the player once the client signals the end of the last tween
-- (EndGameFinishedEvent). One pending entry per player at most.
local pendingEarned = {}
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
local EndGameButtonModule = {
	enter = function(self, player, mode, baseCash, multiplier, earned, lossMultiplier)
		ButtonSessionService:cleanup(player)
		UiService:HideCurrent(player)
		local _player = player
		local _earned = earned
		pendingEarned[_player] = _earned
		task.spawn(function()
			if mode == "released" then
				task.wait(RELEASE_DELAY)
			else
				waitForRespawn(player)
			end
			-- Player may have disconnected while we were waiting
			if player.Parent == nil then
				local _player_1 = player
				pendingEarned[_player_1] = nil
				return nil
			end
			UiService:Show(player, PopupType.ButtonFinishGame)
			Events.EndGameStartEvent:FireClient(player, baseCash, multiplier, lossMultiplier)
		end)
	end,
	enterRewardOnly = function(self, player, reward)
		ButtonSessionService:cleanup(player)
		UiService:HideCurrent(player)
		local _player = player
		local _reward = reward
		pendingEarned[_player] = _reward
		Events.LossRewardEvent:FireClient(player, reward)
	end,
	cancelPending = function(self, player)
		local _player = player
		pendingEarned[_player] = nil
		UiService:Hide(player, PopupType.ButtonFinishGame)
	end,
	init = function(self)
		Events.EndGameFinishedEvent.OnServerEvent:Connect(function(player)
			local _player = player
			local _condition = pendingEarned[_player]
			if _condition == nil then
				_condition = 0
			end
			local earned = _condition
			local _player_1 = player
			pendingEarned[_player_1] = nil
			if earned > 0 then
				PlayerDataService:add(player, "Money", earned)
			end
			UiService:Hide(player, PopupType.ButtonFinishGame)
		end)
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			-- ▼ Map.delete ▼
			local _valueExisted = pendingEarned[_player] ~= nil
			pendingEarned[_player] = nil
			-- ▲ Map.delete ▲
			return _valueExisted
		end)
	end,
}
return {
	EndGameButtonModule = EndGameButtonModule,
}
