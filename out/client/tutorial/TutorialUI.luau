-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
-- bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
-- le bandeau d'instruction. Détruit intégralement à la fin du tutorial.
local GUI_NAME = "TutorialUI"
local IN_GAME_UI = "InGameUI"
-- Au-dessus de InGameUI (qui n'a pas de DisplayOrder explicite, donc 0).
local DISPLAY_ORDER = 100
local screenGui
local banner
local label
local function playerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end
local TutorialUI
TutorialUI = {
	getInGameUI = function(self)
		local found = playerGui():FindFirstChild(IN_GAME_UI)
		local _result = found
		if _result ~= nil then
			_result = _result:IsA("ScreenGui")
		end
		return if _result then found else nil
	end,
	ensure = function(self)
		if screenGui and screenGui.Parent ~= nil then
			return screenGui
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.DisplayOrder = DISPLAY_ORDER
		-- Aligner l'inset sur celui du GUI du jeu, sinon tous les rectangles de cible
		-- seraient décalés de la hauteur de la barre Roblox.
		local _result = TutorialUI:getInGameUI()
		if _result ~= nil then
			_result = _result.IgnoreGuiInset
		end
		local _condition = _result
		if _condition == nil then
			_condition = false
		end
		gui.IgnoreGuiInset = _condition
		gui.Parent = playerGui()
		screenGui = gui
		local frame = Instance.new("Frame")
		frame.Name = "InstructionBanner"
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, -24)
		frame.Size = UDim2.new(0.9, 0, 0, 64)
		frame.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
		frame.BackgroundTransparency = 0.25
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = gui
		banner = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.5
		stroke.Parent = frame
		local text = Instance.new("TextLabel")
		text.Name = "InstructionText"
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(1, -24, 1, -12)
		text.Position = UDim2.new(0, 12, 0, 6)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextWrapped = true
		text.Text = ""
		text.Parent = frame
		label = text
		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = 22
		textSize.Parent = text
		return gui
	end,
	setText = function(self, value)
		TutorialUI:ensure()
		if not banner or not label then
			return nil
		end
		label.Text = value
		banner.Visible = value ~= ""
	end,
	hideBanner = function(self)
		if banner then
			banner.Visible = false
		end
	end,
	destroy = function(self)
		if screenGui then
			screenGui:Destroy()
		end
		screenGui = nil
		banner = nil
		label = nil
	end,
}
return {
	TutorialUI = TutorialUI,
}
