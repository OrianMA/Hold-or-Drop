-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
-- Opens / closes the Shop menu (MainUI/ShopMenu).
-- The ProximityPrompt under Workspace/Shop/ProximityPromptPart opens it; the
-- CloseButton under ShopMenu/Header closes it. Also auto-closes when the
-- player walks more than CLOSE_DISTANCE studs away from the prompt part.
-- Purely client-side — opening a menu needs no server authority (purchases
-- get validated server-side later).
local SHOP_MODEL = "Shop"
local PROMPT_PART = "ProximityPromptPart"
local SHOP_MENU = "ShopMenu"
local HEADER = "Header"
local CLOSE_BUTTON = "CloseButton"
local CLOSE_DISTANCE = 15
local function init()
	local shop = Workspace:WaitForChild(SHOP_MODEL)
	local promptPart = shop:WaitForChild(PROMPT_PART)
	local prompt = promptPart:WaitForChild("ProximityPrompt")
	local mainUI = (Players.LocalPlayer:WaitForChild("PlayerGui")):WaitForChild("MainUI")
	local shopMenu = mainUI:WaitForChild(SHOP_MENU)
	local closeButton = shopMenu:WaitForChild(HEADER):WaitForChild(CLOSE_BUTTON)
	shopMenu.Visible = false
	-- Heartbeat watcher is only attached while the menu is open so the closed
	-- state has zero per-frame cost.
	local distanceWatcher
	local close = function()
		shopMenu.Visible = false
		local _result = distanceWatcher
		if _result ~= nil then
			_result:Disconnect()
		end
		distanceWatcher = nil
	end
	local open = function()
		shopMenu.Visible = true
		local _result = distanceWatcher
		if _result ~= nil then
			_result:Disconnect()
		end
		distanceWatcher = RunService.Heartbeat:Connect(function()
			local _result_1 = Players.LocalPlayer.Character
			if _result_1 ~= nil then
				_result_1 = _result_1:FindFirstChild("HumanoidRootPart")
			end
			local root = _result_1
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
