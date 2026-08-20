-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
-- Opens / closes the Rebirth menu (InGameUI/RebirthMenu).
-- The HUD button InGameUI/HUD/ButtonsFrame/RebirthFrame/ImageButton opens it, and so
-- does the progression bar's RebirthButton once a rebirth is affordable (see
-- HudProgressionController, which calls openRebirthMenu). The CloseButton under
-- RebirthMenu/CloseFrame closes it. Opening hides the persistent HUD; closing brings
-- it back. Purely client-side — opening a menu needs no server authority (the actual
-- rebirth purchase is validated server-side in RebirthService).
local rebirthMenu
-- Shared by every entry point that opens the popup.
local function openRebirthMenu()
	if not rebirthMenu then
		return nil
	end
	rebirthMenu.Visible = true
	InGameUIController:disable()
end
local function init()
	local inGameUI = (Players.LocalPlayer:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local hud = inGameUI:WaitForChild("HUD")
	local openButton = hud:WaitForChild("ButtonsFrame"):WaitForChild("RebirthFrame"):WaitForChild("ImageButton")
	rebirthMenu = inGameUI:WaitForChild("RebirthMenu")
	local closeButton = rebirthMenu:WaitForChild("CloseFrame"):WaitForChild("CloseButton")
	rebirthMenu.Visible = false
	openButton.Activated:Connect(openRebirthMenu)
	closeButton.Activated:Connect(function()
		if rebirthMenu then
			rebirthMenu.Visible = false
		end
		InGameUIController:enable()
	end)
end
return {
	openRebirthMenu = openRebirthMenu,
	init = init,
}
