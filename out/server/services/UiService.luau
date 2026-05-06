-- Compiled with roblox-ts v3.0.0
local config = {}
local currentPopup = {}
local UiService = {
	init = function(self, popupConfig)
		config = popupConfig
	end,
	Show = function(self, player, popupType)
		local _player = player
		local current = currentPopup[_player]
		if current ~= nil then
			local _result = self:FindPopup(current)
			if _result ~= nil then
				_result:Hide(player)
			end
		end
		local _player_1 = player
		local _popupType = popupType
		currentPopup[_player_1] = _popupType
		local _result = self:FindPopup(popupType)
		if _result ~= nil then
			_result:Show(player)
		end
	end,
	Hide = function(self, player, popupType)
		local _result = self:FindPopup(popupType)
		if _result ~= nil then
			_result:Hide(player)
		end
		local _player = player
		if currentPopup[_player] == popupType then
			local _player_1 = player
			currentPopup[_player_1] = nil
		end
	end,
	HideCurrent = function(self, player)
		local _player = player
		local current = currentPopup[_player]
		if current ~= nil then
			self:Hide(player, current)
		end
	end,
	FindPopup = function(self, popupType)
		-- ▼ ReadonlyArray.find ▼
		local _callback = function(c)
			return c.type == popupType
		end
		local _result
		for _i, _v in config do
			if _callback(_v, _i - 1, config) == true then
				_result = _v
				break
			end
		end
		-- ▲ ReadonlyArray.find ▲
		local entry = _result
		if not entry then
			return nil
		end
		return entry.class.new()
	end,
}
return {
	UiService = UiService,
}
