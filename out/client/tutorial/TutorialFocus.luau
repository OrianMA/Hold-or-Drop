-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RunService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").RunService
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
-- Mise en avant d'une cible GUI.
--   "dim"       → 4 frames autour du rectangle de la cible : la cible reste CLIQUABLE
--                 (rien par-dessus), tout le reste est couvert par des frames qui
--                 absorbent l'input (Active = true).
--   "highlight" → contour pulsé sur la cible, SANS assombrir (steps en vol : la fusée
--                 doit rester visible). On ne touche JAMAIS à la taille de la cible :
--                 une interruption laisserait le GUI du jeu déformé.
local DIM_COLOR = Color3.fromRGB(0, 0, 0)
local DIM_TRANSPARENCY = 0.55
local STROKE_NAME = "TutorialHighlightStroke"
local STROKE_COLOR = Color3.fromRGB(255, 226, 92)
local STROKE_MIN = 2
local STROKE_MAX = 6
local PULSE_SPEED = 5
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
	frame.Active = true
	frame.Parent = parent
	return frame
end
-- Place les 4 bandes autour du rectangle (x, y, w, h) de la cible.
local function layoutDim(target)
	if #dimFrames < 4 then
		return nil
	end
	local pos = target.AbsolutePosition
	local size = target.AbsoluteSize
	-- haut
	dimFrames[1].Position = UDim2.new(0, 0, 0, 0)
	dimFrames[1].Size = UDim2.new(1, 0, 0, math.max(pos.Y, 0))
	-- bas
	dimFrames[2].Position = UDim2.new(0, 0, 0, pos.Y + size.Y)
	dimFrames[2].Size = UDim2.new(1, 0, 1, -(pos.Y + size.Y))
	-- gauche
	dimFrames[3].Position = UDim2.new(0, 0, 0, pos.Y)
	dimFrames[3].Size = UDim2.new(0, math.max(pos.X, 0), 0, size.Y)
	-- droite
	dimFrames[4].Position = UDim2.new(0, pos.X + size.X, 0, pos.Y)
	dimFrames[4].Size = UDim2.new(1, -(pos.X + size.X), 0, size.Y)
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
