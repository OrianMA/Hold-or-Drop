-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RunService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").RunService
local _TutorialUI = TS.import(script, script.Parent, "TutorialUI")
local TutorialUI = _TutorialUI.TutorialUI
local Z_DIM = _TutorialUI.Z_DIM
-- Mise en avant d'une cible GUI.
--   "dim"       → 4 frames autour du rectangle de la cible : la cible reste visible,
--                 tout le reste est assombri. PUREMENT VISUEL (Active = false) : le
--                 dim MONTRE où regarder, il ne bloque plus rien — c'est TutorialGate
--                 (lockGui) qui est l'unique mécanisme de blocage de l'input. Ne pas
--                 repasser Active à true en pensant "restaurer" un blocage : il n'y en
--                 a jamais eu ici, et ça recouvrirait le bouton Skip (DisplayOrder 100
--                 de TutorialUI est au-dessus de InGameUI).
--   "highlight" → contour pulsé sur la cible, SANS assombrir — pour un step où la scène
--                 derrière doit rester visible. On ne touche JAMAIS à la taille de la
--                 cible : une interruption laisserait le GUI du jeu déformé.
-- Le contour pulsé est posé dans les DEUX modes ; seul le dim est optionnel.
local DIM_COLOR = Color3.fromRGB(0, 0, 0)
local DIM_TRANSPARENCY = 0.55
local STROKE_NAME = "TutorialHighlightStroke"
local STROKE_COLOR = Color3.fromRGB(255, 226, 92)
local STROKE_MIN = 2
local STROKE_MAX = 6
local PULSE_SPEED = 5
-- Marge, en pixels, entre le rectangle de la cible et le trou laissé dans le dim. Sans
-- elle les bandes sombres viennent mordre le contour pulsé, qui est dessiné EN DEHORS de
-- la cible (ApplyStrokeMode.Border) et atteint STROKE_MAX d'épaisseur au pic de la pulse.
-- En pixels et non en scale : le contour lui-même est en pixels, la marge doit le suivre.
local HOLE_PADDING = STROKE_MAX + 6
local dimFrames = {}
local stroke
local renderConn
local elapsed = 0
local function makeDimFrame(parent)
	local frame = Instance.new("Frame")
	frame.Name = "TutorialDim"
	frame.BackgroundColor3 = DIM_COLOR
	frame.BackgroundTransparency = DIM_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.ZIndex = Z_DIM
	frame.Active = false
	frame.Parent = parent
	return frame
end
-- Place les 4 bandes autour du rectangle de la cible, élargi de HOLE_PADDING pour que le
-- contour pulsé tienne dans le trou.
local function layoutDim(target)
	if #dimFrames < 4 then
		return nil
	end
	-- La cible vit dans InGameUI, les bandes dans TutorialUI : deux ScreenGuis, deux
	-- repères de coordonnées différents (voir TutorialUI.originOffset). On lit l'offset
	-- à CHAQUE appel plutôt que de le mettre en cache — l'appel se fait déjà à chaque
	-- frame (voir RenderStepped ci-dessous), donc toute reconstruction de TutorialUI
	-- (cadre de référence recréé) est automatiquement suivie.
	local origin = TutorialUI:originOffset()
	local pos = target.AbsolutePosition - origin
	local size = target.AbsoluteSize
	-- Bords du trou. La marge n'agrandit QUE le trou : la cible elle-même n'est jamais
	-- touchée (une interruption laisserait le GUI du jeu déformé).
	local left = pos.X - HOLE_PADDING
	local top = pos.Y - HOLE_PADDING
	local right = pos.X + size.X + HOLE_PADDING
	local bottom = pos.Y + size.Y + HOLE_PADDING
	local holeHeight = bottom - top
	-- haut
	dimFrames[1].Position = UDim2.new(0, 0, 0, 0)
	dimFrames[1].Size = UDim2.new(1, 0, 0, math.max(top, 0))
	-- bas
	dimFrames[2].Position = UDim2.new(0, 0, 0, bottom)
	dimFrames[2].Size = UDim2.new(1, 0, 1, -bottom)
	-- gauche
	dimFrames[3].Position = UDim2.new(0, 0, 0, top)
	dimFrames[3].Size = UDim2.new(0, math.max(left, 0), 0, holeHeight)
	-- droite
	dimFrames[4].Position = UDim2.new(0, right, 0, top)
	dimFrames[4].Size = UDim2.new(1, -right, 0, holeHeight)
end
local TutorialFocus
TutorialFocus = {
	apply = function(self, target, mode)
		TutorialFocus:clear()
		local gui = TutorialUI:ensure()
		if mode == "dim" then
			for i = 0, 3 do
				local _dimFrames = dimFrames
				local _arg0 = makeDimFrame(gui)
				table.insert(_dimFrames, _arg0)
			end
			layoutDim(target)
		end
		local outline = Instance.new("UIStroke")
		outline.Name = STROKE_NAME
		outline.Color = STROKE_COLOR
		outline.Thickness = STROKE_MIN
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Parent = target
		stroke = outline
		renderConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			if stroke then
				local t = (math.sin(elapsed * PULSE_SPEED) + 1) / 2
				stroke.Thickness = STROKE_MIN + (STROKE_MAX - STROKE_MIN) * t
			end
			-- La cible peut bouger/se redimensionner (layouts, tweens) → on suit.
			if #dimFrames > 0 then
				layoutDim(target)
			end
		end)
	end,
	clear = function(self)
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		elapsed = 0
		for _, frame in dimFrames do
			frame:Destroy()
		end
		dimFrames = {}
		if stroke then
			stroke:Destroy()
			stroke = nil
		end
	end,
}
return {
	TutorialFocus = TutorialFocus,
}
