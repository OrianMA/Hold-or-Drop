-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
local NOT_ENOUGH_MONEY_TEXT = "Not enough money"
local NOT_ENOUGH_MONEY_COLOR = Color3.new(1, 0.25, 0.25)
local NOT_ENOUGH_MONEY_HOLD = 2.5
local UI_PART_NAME = "UiPart"
local BILLBOARD_NAME = "BillboardGui"
local GAIN_LABEL = "GainText"
local COST_LABEL = "CostText"
local POSSESSED_TEXT = "POSSESSED"
local ButtonModule
do
	ButtonModule = setmetatable({}, {
		__tostring = function()
			return "ButtonModule"
		end,
	})
	ButtonModule.__index = ButtonModule
	function ButtonModule.new(...)
		local self = setmetatable({}, ButtonModule)
		return self:constructor(...) or self
	end
	function ButtonModule:constructor()
	end
	function ButtonModule:init(model)
		self.playerPosPart = model:FindFirstChild("PlayerPosPlaceHolder")
		self.cameraPosPart = model:FindFirstChild("CameraPosPart")
		local _result = model:FindFirstChild("ButtonPart")
		if _result ~= nil then
			_result = _result:FindFirstChildOfClass("ProximityPrompt")
		end
		self.proximityPrompt = _result
		if not self.playerPosPart or not self.cameraPosPart or not self.proximityPrompt then
			warn(`ButtonModule: Missing parts in {model.Name}`)
			return nil
		end
		local _condition = (model:GetAttribute("BaseCash"))
		if _condition == nil then
			_condition = 10000
		end
		self.baseCash = _condition
		local _condition_1 = (model:GetAttribute("Cost"))
		if _condition_1 == nil then
			_condition_1 = 0
		end
		self.cost = _condition_1
		-- DataName is the persistence key — falls back to model name so the
		-- system still works if the attribute hasn't been authored yet.
		local _condition_2 = (model:GetAttribute("DataName"))
		if _condition_2 == nil then
			_condition_2 = model.Name
		end
		self.dataName = _condition_2
		local uiPart = model:FindFirstChild(UI_PART_NAME)
		local _billboard = uiPart
		if _billboard ~= nil then
			_billboard = _billboard:FindFirstChild(BILLBOARD_NAME)
		end
		local billboard = _billboard
		local _result_1 = billboard
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("BillboardGui")
		end
		if _result_1 then
			self.billboardGui = billboard
		end
		-- Initial UI sync — server-side property writes replicate to all
		-- clients, so the labels show the right values from the very first
		-- frame instead of whatever was authored in Studio. The "POSSESSED"
		-- override for unlocked players still happens client-side
		-- (ButtonLabelsController) since that's per-player state.
		self:syncLabels(model)
		self.proximityPrompt.ObjectText = `{FormatCash(self.baseCash)} money`
		self.proximityPrompt.Triggered:Connect(function(player)
			return self:onTriggered(player)
		end)
	end
	function ButtonModule:syncLabels(model)
		local uiPart = model:FindFirstChild(UI_PART_NAME)
		if not uiPart then
			return nil
		end
		local gainLabel = uiPart:FindFirstChild(GAIN_LABEL, true)
		local _result = gainLabel
		if _result ~= nil then
			_result = _result:IsA("TextLabel")
		end
		if _result then
			gainLabel.Text = FormatCash(self.baseCash)
		end
		local costLabel = uiPart:FindFirstChild(COST_LABEL, true)
		-- Default = "locked" state. Client overrides to "POSSESSED" per-player.
		-- Free buttons (cost <= 0) are always owned — show POSSESSED to everyone.
		local _result_1 = costLabel
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("TextLabel")
		end
		if _result_1 then
			costLabel.Text = if self.cost <= 0 then POSSESSED_TEXT else `{FormatCash(self.cost)} money`
		end
	end
	function ButtonModule:onTriggered(player)
		local character = player.Character
		if not character then
			return nil
		end
		-- ── Purchase gate ─────────────────────────────────────────────────────
		-- If the player hasn't unlocked this button, this trigger is an attempt
		-- to buy it.
		--   • Free buttons (cost <= 0) skip the gate entirely — owned by default.
		--   • Not enough money → flash the info text and bail out.
		--   • Enough money     → debit, flag as owned, and stop — the trigger
		--     just completed the purchase. The player has to interact with the
		--     button a second time to actually enter the game.
		if self.cost > 0 and not PlayerDataService:isButtonUnlocked(player, self.dataName) then
			local money = PlayerDataService:get(player, "Money")
			if money < self.cost then
				Events.InformationTextEvent:FireClient(player, NOT_ENOUGH_MONEY_TEXT, NOT_ENOUGH_MONEY_COLOR, NOT_ENOUGH_MONEY_HOLD)
				return nil
			end
			PlayerDataService:add(player, "Money", -self.cost)
			PlayerDataService:setButtonUnlocked(player, self.dataName)
			return nil
		end
		ButtonSessionService:setSession(player, {
			baseCash = self.baseCash,
			proximityPrompt = self.proximityPrompt,
			billboardGui = self.billboardGui,
		})
		-- Hide the floating label-billboard for the active player only — restored
		-- when ButtonSessionService.cleanup() runs at the end of the session.
		if self.billboardGui then
			self.billboardGui.PlayerToHideFrom = player
		end
		Events.ButtonTriggerEvent:FireClient(player, self.cameraPosPart)
		self:teleportPlayer(character)
		self.proximityPrompt.Enabled = false
		UiService:Show(player, PopupType.ButtonMenu)
	end
	function ButtonModule:teleportPlayer(character)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return nil
		end
		local playerSize = character:GetExtentsSize().Y
		local _cFrame = self.playerPosPart.CFrame
		local _vector3 = Vector3.new(0, playerSize / 2, 0)
		hrp.CFrame = _cFrame + _vector3
		hrp.Anchored = true
	end
end
return {
	ButtonModule = ButtonModule,
}
