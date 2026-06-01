-- Compiled with roblox-ts v3.0.0
local sessions = {}
local ButtonSessionService = {
	setSession = function(self, player, session)
		local _player = player
		local _session = session
		sessions[_player] = _session
	end,
	getSession = function(self, player)
		local _player = player
		return sessions[_player]
	end,
	clearSession = function(self, player)
		local _player = player
		sessions[_player] = nil
	end,
	cleanup = function(self, player)
		local _player = player
		local session = sessions[_player]
		if session then
			local room = session.room
			-- PlayerToHideFrom was set to this player on trigger — clear it so the
			-- billboard becomes visible to them again.
			if room.billboardGui and room.billboardGui.PlayerToHideFrom == player then
				room.billboardGui.PlayerToHideFrom = nil
			end
		end
		-- Session over — the owner's client re-enables their prompt (RoomPromptController).
		player:SetAttribute("InSession", false)
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = false
			end
		end
		local _player_1 = player
		sessions[_player_1] = nil
	end,
}
return {
	ButtonSessionService = ButtonSessionService,
}
