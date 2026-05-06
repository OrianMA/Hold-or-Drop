-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
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
		self.proximityPrompt.Triggered:Connect(function(player)
			return self:onTriggered(player)
		end)
	end
	function ButtonModule:onTriggered(player)
		local character = player.Character
		if not character then
			return nil
		end
		ButtonSessionService:setSession(player, {
			baseCash = self.baseCash,
			proximityPrompt = self.proximityPrompt,
		})
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
