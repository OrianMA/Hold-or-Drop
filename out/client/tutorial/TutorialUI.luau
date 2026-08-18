-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local GuiService = _services.GuiService
local Players = _services.Players
-- Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
-- bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
-- le bandeau d'instruction. Détruit intégralement à la fin du tutorial.
local GUI_NAME = "TutorialUI"
local IN_GAME_UI = "InGameUI"
-- Au-dessus de InGameUI (mesuré à DisplayOrder = 1).
local DISPLAY_ORDER = 100
-- Empilement à l'intérieur de TutorialUI. Sans ZIndex explicite, tout vaut 1 et c'est
-- l'ORDRE DE CRÉATION qui décide : les bandes de dim, créées après le bandeau, passaient
-- donc par-dessus et assombrissaient l'instruction elle-même.
-- Ces valeurs n'ordonnent QUE des frères : elles supposent ZIndexBehavior = Sibling,
-- fixé explicitement dans ensure() (voir le commentaire là-bas).
local Z_DIM = 1
local Z_ARROW = 5
local Z_BANNER = 10
-- Bord supérieur par défaut du bandeau, en scale — utilisé quand le step n'a pas de
-- TutorialStep.textY. Voir le bloc de mesures ci-dessous dans ensure().
local DEFAULT_BANNER_Y = 0.12
local screenGui
local banner
local label
local originFrame
local function playerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end
-- SEUL offset en pixels autorisé sur le bandeau : la barre Roblox. Le ScreenGui du
-- tutorial recopie IgnoreGuiInset de InGameUI (= true), donc y = 0 tombe SOUS la barre
-- système. Cette hauteur est en pixels par nature (~36 px, indépendante du viewport) :
-- l'exprimer en scale masquerait le bandeau sur les écrans bas (paysage téléphone).
local function topInsetPixels()
	local _result = screenGui
	if _result ~= nil then
		_result = _result.IgnoreGuiInset
	end
	if not _result then
		return 0
	end
	local topLeft = GuiService:GetGuiInset()
	return topLeft.Y
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
		-- EXPLICITE, ne pas retirer : en ZIndexBehavior.Global tous les GuiObject sont triés
		-- à plat, donc le cadre du bandeau (Z_BANNER) passerait DEVANT son propre TextLabel
		-- (ZIndex 1) et son fond noir à 0.25 de transparence grisait le texte. En Sibling,
		-- un descendant est toujours dessiné au-dessus de son parent et les constantes
		-- Z_* n'ordonnent que les frères — c'est ce qu'elles décrivent.
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
		-- Bandes occupées par le jeu, mesurées dans Studio et exprimées en fractions
		-- d'écran, DÉJÀ corrigées par originOffset() (repère du ScreenGui du tutorial, pas
		-- celui de InGameUI — une mesure prise dans le mauvais repère est précisément ce qui
		-- faisait chevaucher StartButton avant ce correctif) :
		--   ButtonMenu/StartButton           y 0.570→0.670
		--   ButtonMenu/QuitButton            y 0.750→0.850
		--   RocketLaunch/MultiplierText      y 0.105→0.227
		--   RocketLaunch/ClaimButtonFrame    y 0.771→0.908
		--   RocketLaunch/ResultMultiplier    y 0.799→0.849
		--   ButtonFinishGame/FinishText      y 0.110→0.190
		--   ButtonFinishGame/MultiplierText  y 0.283→0.383
		--   ButtonFinishGame/BaseCashText    y 0.748→0.848
		--   ShopMenu (panneau entier)        y 0.150→0.885
		--   HUD/MoneyParent                  y 0.211→0.289  (x 0.030→0.241 seulement)
		--   HUD/BottomList                   y 0.855→0.945
		-- Le bandeau vit dans le TIERS HAUT de l'écran, sous le multiplicateur du run
		-- (RocketLaunch/MultiplierText occupe y 0.105→0.227, mais son texte ne remplit pas
		-- tout ce rectangle) : DEFAULT_BANNER_Y le pose en 0.12→0.20, + l'inset de la barre
		-- Roblox (voir topInsetPixels). Position validée en jeu sur le step claim.
		-- Le milieu est interdit (c'est là que se projettent les cibles monde, donc la
		-- traînée de flèches, mesurée à y≈0.38 pour le bouton de la room) et le bas est pris
		-- par les boutons d'action + le bouton Skip (y 0.87→0.95).
		-- Un step dont la cible mange ce tiers haut remonte le bandeau tout en haut via
		-- TutorialStep.textY (voir TutorialTypes.ts) — c'est le cas de buy-rocket-speed, dont
		-- le panneau ShopMenu démarre à y 0.150 ; setText() en tient compte.
		-- Largeur 0.58 centrée (x 0.21→0.79) : les colonnes latérales sont libres à cette
		-- hauteur (ButtonsFrame démarre à y 0.31), donc le bandeau peut être plus large
		-- qu'un bandeau centré — moins de retour à la ligne, donc un texte plus gros.
		-- Position Y, largeur et hauteur restent en scale (hors inset barre Roblox) : un
		-- offset en pixels rendrait la marge dépendante de la hauteur du viewport.
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, DEFAULT_BANNER_Y, topInsetPixels())
		frame.Size = UDim2.new(0.58, 0, 0.08, 0)
		frame.ZIndex = Z_BANNER
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
		textSize.MaxTextSize = 30
		textSize.Parent = text
		return gui
	end,
	originOffset = function(self)
		TutorialUI:ensure()
		return if originFrame then originFrame.AbsolutePosition else Vector2.new(0, 0)
	end,
	setText = function(self, value, y)
		TutorialUI:ensure()
		if not banner or not label then
			return nil
		end
		label.Text = value
		banner.Visible = value ~= ""
		local position = banner.Position
		local _exp = position.X.Scale
		local _exp_1 = position.X.Offset
		local _condition = y
		if _condition == nil then
			_condition = DEFAULT_BANNER_Y
		end
		banner.Position = UDim2.new(_exp, _exp_1, _condition, topInsetPixels())
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
	Z_DIM = Z_DIM,
	Z_ARROW = Z_ARROW,
	Z_BANNER = Z_BANNER,
	DEFAULT_BANNER_Y = DEFAULT_BANNER_Y,
	TutorialUI = TutorialUI,
}
