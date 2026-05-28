-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local MainUIController = TS.import(script, script.Parent, "MainUIController").MainUIController
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- Renders the local player's Money attribute into a TextLabel named "MoneyText"
-- sitting under MoneyParent inside MainUI. The attribute is set by the server
-- (PlayerDataService) and auto-replicates to this client.
local ATTRIBUTE = "Money"
local LABEL_NAME = "MoneyText"
local function findLabel()
	local moneyParent = MainUIController:getMoneyParent()
	if not moneyParent then
		return nil
	end
	local found = moneyParent:FindFirstChild(LABEL_NAME, true)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	return if _result then found else nil
end
local function init()
	local player = Players.LocalPlayer
	local refresh = function()
		local label = findLabel()
		if not label then
			return nil
		end
		local _condition = (player:GetAttribute(ATTRIBUTE))
		if _condition == nil then
			_condition = 0
		end
		local value = _condition
		label.Text = FormatCash(value)
	end
	refresh()
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(refresh)
	-- Label may not exist yet on first frame — re-render on new descendants
	local gui = player:WaitForChild("PlayerGui")
	gui.DescendantAdded:Connect(function(desc)
		if desc.Name == LABEL_NAME and desc:IsA("TextLabel") then
			refresh()
		end
	end)
end
return {
	init = init,
}
