-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local rebirthCost = _ShopConfig.rebirthCost
local rebirthMult = _ShopConfig.rebirthMult
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
-- Binds the shop Rebirth panel (MainUI/ShopMenu/Body/RebirthPanel), which reuses
-- the same frame structure as the upgrade items. Read-only display driven by the
-- replicated Money + Rebirths attributes; the buy button fires RebirthEvent. The
-- server re-validates, so the client guard here is purely for instant UX.
local player = Players.LocalPlayer
local function getRebirths()
	local _condition = (player:GetAttribute("Rebirths"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function getMoney()
	local _condition = (player:GetAttribute("Money"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
-- "×2", "×3.5" — trim trailing zeros.
local function formatMult(value)
	local hundredths = math.floor(value * 100 + 1e-7)
	local trimmed = if hundredths % 100 == 0 then tostring(hundredths / 100) else string.format("%.2f", hundredths / 100)
	return `×{trimmed}`
end
local function setAffordable(button, priceLabel, affordable)
	button.AutoButtonColor = affordable
	button.BackgroundTransparency = if affordable then 0 else 0.6
	priceLabel.TextTransparency = if affordable then 0 else 0.4
end
local function init()
	local mainUI = (player:WaitForChild("PlayerGui")):WaitForChild("MainUI")
	local panel = mainUI:WaitForChild("ShopMenu"):WaitForChild("Body"):WaitForChild("RebirthPanel")
	local boost = panel:WaitForChild("BoostLyout")
	local titleText = boost:WaitForChild("BoostTitleText")
	local currentText = boost:WaitForChild("CurrentStatFrame"):WaitForChild("CurrentStatText")
	local nextText = boost:WaitForChild("NextStatFrame"):WaitForChild("NextStatText")
	local buyButton = panel:WaitForChild("ButtonsLayout"):WaitForChild("BuyButton")
	local priceLabel = buyButton:WaitForChild("TextLabel")
	titleText.Text = "Rebirth"
	local function refresh()
		local rebirths = getRebirths()
		local cost = rebirthCost(rebirths)
		currentText.Text = formatMult(rebirthMult(rebirths))
		nextText.Text = formatMult(rebirthMult(rebirths + 1))
		priceLabel.Text = `{FormatNumber(cost)}$`
		setAffordable(buyButton, priceLabel, getMoney() >= cost)
	end
	buyButton.Activated:Connect(function()
		if getMoney() < rebirthCost(getRebirths()) then
			return nil
		end
		Events.RebirthEvent:FireServer()
	end)
	player:GetAttributeChangedSignal("Money"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	refresh()
end
return {
	init = init,
}
