-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
-- bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
-- le bandeau d'instruction. Détruit intégralement à la fin du tutorial.
local GUI_NAME = "TutorialUI"
local IN_GAME_UI = "InGameUI"
-- Au-dessus de InGameUI (mesuré à DisplayOrder = 1).
local DISPLAY_ORDER = 100
local screenGui
local banner
local label
local originFrame
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
		-- Repère de coordonnées de CE ScreenGui. InGameUI et TutorialUI n'ont pas la même
		-- origine (mesuré en Studio : InGameUI.HUD rapporte AbsolutePosition.Y = -58 alors
		-- que TutorialUI démarre à 0) — aligner IgnoreGuiInset ne corrige pas cet écart.
		-- Ce cadre plein écran, transparent et non-interactif sert uniquement à lire son
		-- AbsolutePosition : soustraire cette valeur convertit un point du repère de
		-- InGameUI vers celui de TutorialUI, quelle qu'en soit la cause sur l'appareil.
		local origin = Instance.new("Frame")
		origin.Name = "TutorialOrigin"
		origin.Size = UDim2.new(1, 0, 1, 0)
		origin.Position = UDim2.new(0, 0, 0, 0)
		origin.BackgroundTransparency = 1
		origin.Active = false
		origin.Parent = gui
		originFrame = origin
		local frame = Instance.new("Frame")
		frame.Name = "InstructionBanner"
		-- Placement ENTIÈREMENT en scale — position ET taille — pour que le rectangle occupe
		-- la même fraction d'écran partout (le jeu est mobile-first, et le paysage
		-- téléphone descend vers 375 px de haut). Le moindre offset en pixels rendrait la
		-- marge dépendante de la hauteur du viewport : avec une hauteur fixe de 64 px, le
		-- bas du bandeau touchait le bouton Start dès que la hauteur d'écran passait sous
		-- ~388 px.
		--
		-- Bandes occupées par le jeu, mesurées dans Studio et exprimées en fractions :
		--   MoneyParent   y 0.21→0.29  (sa LARGEUR dépend d'un UIAspectRatioConstraint,
		--                               donc du viewport : seule sa bande verticale est fiable)
		--   ButtonsFrame  x 0.013→0.24, y 0.31→0.75   (scale pur)
		--   StartButton   y 0.505→0.605
		--   Claim/Result  y 0.71→0.84
		--   BottomList    y 0.855→0.945              (scale pur)
		-- Le bandeau se glisse dans le couloir libre entre Start et Claim : y 0.625→0.685,
		-- soit 0.02 de marge de chaque côté. Le milieu de l'écran est INTERDIT : c'est là que
		-- se projettent les cibles monde, donc la traînée de flèches (mesuré à y≈0.38 pour le
		-- bouton de la room) — un bandeau centré verticalement la recouvrait entièrement.
		-- Largeur 0.46 centrée (x 0.27→0.73) pour laisser 3 points à la colonne ButtonsFrame.
		-- Ces trois nombres (Y, largeur, hauteur) sont les seuls leviers — les garder en
		-- scale, jamais en offset : un offset en pixels rend la marge dépendante du viewport.
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0.625, 0)
		frame.Size = UDim2.new(0.46, 0, 0.06, 0)
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
	originOffset = function(self)
		TutorialUI:ensure()
		return if originFrame then originFrame.AbsolutePosition else Vector2.new(0, 0)
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
		originFrame = nil
	end,
}
return {
	TutorialUI = TutorialUI,
}
