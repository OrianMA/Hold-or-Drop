-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local rebirthCost = _ShopConfig.rebirthCost
local rebirthMult = _ShopConfig.rebirthMult
local SAFE_REBIRTH_PRODUCT_ID = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RebirthProducts").SAFE_REBIRTH_PRODUCT_ID
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local InformationText = TS.import(script, script.Parent.Parent, "ui", "InformationText").InformationText
-- Drives the Rebirth menu display (InGameUI/RebirthMenu) and the buy action.
-- Read-only display fed by the replicated Money + Rebirths attributes; the buy
-- button fires RebirthEvent when affordable, otherwise flashes the information
-- panel. The server (RebirthService) re-validates, so the client guard here is
-- purely for instant UX.
local player = Players.LocalPlayer
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
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
-- "x2", "x3.5" below 1000 (2 decimals, trailing zeros trimmed) ; "x32.77K",
-- "x2.1M" at and above 1000 — delegated to FormatNumber so the rebirth
-- multiplier (8^R, e.g. ×2 097 152 at R7) never prints as a raw 7-9 digit
-- number in a label sized for "x5".
local function formatMult(value)
	if value >= 1000 then
		return `x{FormatNumber(value)}`
	end
	local hundredths = math.floor(value * 100 + 1e-7)
	local trimmed = if hundredths % 100 == 0 then tostring(hundredths / 100) else string.format("%.2f", hundredths / 100)
	return `x{trimmed}`
end
local function init()
	local menu = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("RebirthMenu")
	local info = menu:WaitForChild("RebirthInfoElements")
	local currentRebirth = info:WaitForChild("CurrentRebirth")
	local nextRebirth = info:WaitForChild("NextRebirth")
	local currentTitle = currentRebirth:WaitForChild("RebirthLevelTitle")
	local currentMult = currentRebirth:WaitForChild("Frame"):WaitForChild("MultiplierText")
	local nextTitle = nextRebirth:WaitForChild("RebirthLevelTitle")
	local nextMult = nextRebirth:WaitForChild("Frame"):WaitForChild("MultiplierText")
	local progressionBar = menu:WaitForChild("ProgressionBar")
	local fill = progressionBar:WaitForChild("CurrentProgressionFrame")
	local moneyNeededText = progressionBar:WaitForChild("BackgroundFrame"):WaitForChild("MoneyNeededText")
	local buttonsFrame = menu:WaitForChild("ButtonsFrame")
	local buyButton = buttonsFrame:WaitForChild("RebirthButton"):WaitForChild("Button")
	local safeRebirthButton = buttonsFrame:WaitForChild("SafeRebirthButton"):WaitForChild("Button")
	local function refresh()
		local rebirths = getRebirths()
		local money = getMoney()
		local cost = rebirthCost(rebirths)
		currentTitle.Text = `Rebirth {rebirths}`
		nextTitle.Text = `Rebirth {rebirths + 1}`
		currentMult.Text = `{formatMult(rebirthMult(rebirths))} money`
		nextMult.Text = `{formatMult(rebirthMult(rebirths + 1))} money`
		local progress = math.clamp(money / cost, 0, 1)
		fill.Size = UDim2.new(progress, 0, 1, 0)
		moneyNeededText.Text = `{FormatNumber(money)}/{FormatNumber(cost)}`
	end
	buyButton.Activated:Connect(function()
		if getMoney() < rebirthCost(getRebirths()) then
			InformationText:show("Pas assez d'argent pour le Rebirth", {
				color = DENIED_COLOR,
			})
			return nil
		end
		Events.RebirthEvent:FireServer()
	end)
	-- Safe rebirth — paid Robux dev product. No in-game money gate (that's the point:
	-- rebirth without losing any progression). The native purchase prompt shows the
	-- price; on a successful receipt the server (RebirthService.safeRebirth) grants
	-- +1 Rebirth while keeping Money + upgrades, and the menu refreshes on Rebirths.
	safeRebirthButton.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(player, SAFE_REBIRTH_PRODUCT_ID)
	end)
	player:GetAttributeChangedSignal("Money"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	refresh()
end
return {
	init = init,
}
