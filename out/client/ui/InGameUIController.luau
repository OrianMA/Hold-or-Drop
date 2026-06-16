-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- Centralized control for the persistent HUD container.
-- "HUD" here refers to a Frame (or other GuiObject) named "HUD" that sits
-- INSIDE the InGameUI ScreenGui — sibling to the button-game popups (ButtonMenu,
-- ButtonInGame, ButtonFinishGame). Toggling its Visible hides the HUD while
-- keeping the popups rendering normally.
local function getPlayerGui()
	return Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
-- Walks PlayerGui descendants looking for the GuiObject named "HUD" — the
-- persistent HUD frame nested inside the InGameUI ScreenGui.
local function getHudFrame()
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil
	end
	for _, desc in playerGui:GetDescendants() do
		if desc.Name == "HUD" and desc:IsA("GuiObject") then
			return desc
		end
	end
	return nil
end
local InGameUIController = {
	disable = function(self)
		local frame = getHudFrame()
		if frame then
			frame.Visible = false
		end
	end,
	enable = function(self)
		local frame = getHudFrame()
		if frame then
			frame.Visible = true
		end
	end,
	getMoneyParent = function(self)
		local frame = getHudFrame()
		if not frame then
			return nil
		end
		local found = frame:FindFirstChild("MoneyParent", true)
		local _result = found
		if _result ~= nil then
			_result = _result:IsA("GuiObject")
		end
		return if _result then found else nil
	end,
}
return {
	InGameUIController = InGameUIController,
}
