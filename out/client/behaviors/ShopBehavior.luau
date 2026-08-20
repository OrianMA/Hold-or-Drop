-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
-- Opens / closes the Shop menu (InGameUI/ShopMenu).
-- The ProximityPrompt under Workspace/Shop/ProximityPromptPart opens it; the
-- CloseButton under ShopMenu/Header closes it. Also auto-closes when the
-- player walks more than CLOSE_DISTANCE studs away from the prompt part.
-- Opening hides the persistent HUD; closing brings it back (every close path
-- goes through close(), so the distance auto-close restores it too).
-- Purely client-side — opening a menu needs no server authority (purchases
-- get validated server-side later).
local SHOP_MODEL = "Shop"
local PROMPT_PART = "ProximityPromptPart"
local SHOP_MENU = "ShopMenu"
local MONEY_PARENT = "MoneyParent"
local HEADER = "Header"
local CLOSE_BUTTON = "CloseButton"
local CLOSE_DISTANCE = 15
local function init()
	local shop = Workspace:WaitForChild(SHOP_MODEL)
	local promptPart = shop:WaitForChild(PROMPT_PART)
	local prompt = promptPart:WaitForChild("ProximityPrompt")
	local inGameUI = (Players.LocalPlayer:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local shopMenu = inGameUI:WaitForChild(SHOP_MENU)
	local closeButton = shopMenu:WaitForChild(HEADER):WaitForChild(CLOSE_BUTTON)
	-- MoneyParent (sibling of ShopMenu) mirrors the shop: the HUD's own money
	-- display is hidden with the HUD while shopping, so this one shows the balance
	-- while the shop is open and hides again on close.
	-- OPTIONAL on purpose — it is currently absent from the GUI (only HUD/MoneyParent
	-- exists), and a WaitForChild here yields forever, which takes down every init
	-- AFTER this one in main.client.ts (they run sequentially). A missing money mirror
	-- costs a balance readout while shopping; it must never cost the whole client.
	local found = inGameUI:FindFirstChild(MONEY_PARENT)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("GuiObject")
	end
	local moneyParent = if _result then found else nil
	if not moneyParent then
		warn(`ShopBehavior: InGameUI/{MONEY_PARENT} introuvable — pas d'argent affiché pendant le shop`)
	end
	shopMenu.Visible = false
	if moneyParent then
		moneyParent.Visible = false
	end
	-- Heartbeat watcher is only attached while the menu is open so the closed
	-- state has zero per-frame cost.
	local distanceWatcher
	local close = function()
		shopMenu.Visible = false
		if moneyParent then
			moneyParent.Visible = false
		end
		InGameUIController:enable()
		local _result_1 = distanceWatcher
		if _result_1 ~= nil then
			_result_1:Disconnect()
		end
		distanceWatcher = nil
	end
	local open = function()
		shopMenu.Visible = true
		if moneyParent then
			moneyParent.Visible = true
		end
		InGameUIController:disable()
		local _result_1 = distanceWatcher
		if _result_1 ~= nil then
			_result_1:Disconnect()
		end
		distanceWatcher = RunService.Heartbeat:Connect(function()
			local _result_2 = Players.LocalPlayer.Character
			if _result_2 ~= nil then
				_result_2 = _result_2:FindFirstChild("HumanoidRootPart")
			end
			local root = _result_2
			if not root then
				return nil
			end
			local _position = root.Position
			local _position_1 = promptPart.Position
			if (_position - _position_1).Magnitude > CLOSE_DISTANCE then
				close()
			end
		end)
	end
	prompt.Triggered:Connect(open)
	closeButton.Activated:Connect(close)
end
return {
	init = init,
}
