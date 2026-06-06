-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
-- Opens / closes the Shop menu (MainUI/ShopMenu).
-- The ProximityPrompt under Workspace/Shop/ProximityPromptPart opens it; the
-- CloseButton under ShopMenu/header closes it. Purely client-side — opening a
-- menu needs no server authority (purchases get validated server-side later).
local SHOP_MODEL = "Shop"
local PROMPT_PART = "ProximityPromptPart"
local SHOP_MENU = "ShopMenu"
local HEADER = "header"
local CLOSE_BUTTON = "CloseButton"
local function init()
	local shop = Workspace:WaitForChild(SHOP_MODEL)
	local prompt = shop:WaitForChild(PROMPT_PART):WaitForChild("ProximityPrompt")
	local mainUI = (Players.LocalPlayer:WaitForChild("PlayerGui")):WaitForChild("MainUI")
	local shopMenu = mainUI:WaitForChild(SHOP_MENU)
	local closeButton = shopMenu:WaitForChild(HEADER):WaitForChild(CLOSE_BUTTON)
	shopMenu.Visible = false
	prompt.Triggered:Connect(function()
		shopMenu.Visible = true
	end)
	closeButton.Activated:Connect(function()
		shopMenu.Visible = false
	end)
end
return {
	init = init,
}
