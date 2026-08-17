-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
-- Le pointage du tutorial. Deux modes :
--   • monde  → une TRAÎNÉE de BillboardGui du joueur jusqu'à la cible, qui s'allument
--              l'une après l'autre (chenillard), plus un chevron de bord d'écran quand
--              la cible est hors champ (sinon le joueur ne sait pas où tourner).
--   • GUI    → une flèche à côté du rectangle de la cible, orientée vers elle.
-- Une seule boucle RenderStepped, active uniquement pendant un step qui pointe.
local ARROW_IMAGE = "rbxassetid://104204322044198"
local ARROW_COUNT = 6
local MIN_SPACING = 3
local ARROW_SIZE = 5
local ARROW_HEIGHT = 3
local CHASE_PERIOD = 1.2
local DIM_TRANSPARENCY = 0.75
local GUI_ARROW_SIZE = 64
local GUI_ARROW_GAP = 12
local GUI_BOB = 8
local worldArrows = {}
local chevron
local guiArrow
local renderConn
local elapsed = 0
local function makeImage(parent, size)
	local image = Instance.new("ImageLabel")
	image.Name = "TutorialArrowImage"
	image.BackgroundTransparency = 1
	image.Image = ARROW_IMAGE
	image.Size = size
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.new(0.5, 0, 0.5, 0)
	image.Parent = parent
	return image
end
local function makeWorldArrow()
	-- Une part invisible sert d'ancre au BillboardGui (créée côté client : elle n'existe
	-- que pour ce joueur).
	local part = Instance.new("Part")
	part.Name = "TutorialArrowAnchor"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Locked = true
	part.Parent = Workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialArrow"
	-- Taille en STUDS (offset nul) : la flèche garde sa taille apparente avec la distance.
	billboard.Size = UDim2.new(ARROW_SIZE, 0, ARROW_SIZE, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 500
	billboard.Adornee = part
	billboard.Parent = part
	local image = makeImage(billboard, UDim2.new(1, 0, 1, 0))
	image.Visible = false
	return {
		part = part,
		image = image,
	}
end
local function ensureWorldArrows()
	if #worldArrows > 0 then
		return nil
	end
	for i = 0, ARROW_COUNT - 1 do
		local _worldArrows = worldArrows
		local _arg0 = makeWorldArrow()
		table.insert(_worldArrows, _arg0)
	end
end
local function ensureChevron()
	if chevron and chevron.Parent ~= nil then
		return chevron
	end
	chevron = makeImage(TutorialUI:ensure(), UDim2.new(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE))
	chevron.Name = "TutorialChevron"
	return chevron
end
local function ensureGuiArrow()
	if guiArrow and guiArrow.Parent ~= nil then
		return guiArrow
	end
	guiArrow = makeImage(TutorialUI:ensure(), UDim2.new(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE))
	guiArrow.Name = "TutorialGuiArrow"
	return guiArrow
end
local function stopRender()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end
-- Angle (degrés) du vecteur écran `delta`, avec l'image considérée pointant vers le HAUT
-- à 0°.
local function angleOf(delta)
	return math.deg(math.atan2(delta.X, -delta.Y))
end
local function characterPosition()
	local _hrp = Players.LocalPlayer.Character
	if _hrp ~= nil then
		_hrp = _hrp:FindFirstChild("HumanoidRootPart")
	end
	local hrp = _hrp
	local _result = hrp
	if _result ~= nil then
		_result = _result:IsA("BasePart")
	end
	return if _result then hrp.Position else nil
end
local TutorialArrow
TutorialArrow = {
	pointAtWorld = function(self, part)
		TutorialArrow:clear()
		ensureWorldArrows()
		local chev = ensureChevron()
		renderConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local from = characterPosition()
			local target = part.Position
			-- La caméra doit être lue à chaque frame car elle est nil au spawn
			local camera = Workspace.CurrentCamera
			if not from or not camera then
				-- Masquer toutes les flèches si on n'est pas prêt
				for _, arrow in worldArrows do
					arrow.image.Visible = false
				end
				chev.Visible = false
				return nil
			end
			-- Répartition PROPORTIONNELLE à la distance : selon le step, la cible est entre
			-- ~10 studs (bouton) et ~90 studs (boutique), donc un pas fixe est soit trop
			-- dense sur les trajets courts, soit trop court sur les longs (la traînée
			-- s'arrêterait avant la cible). On calcule combien de flèches tiennent avec un
			-- espacement minimum, puis on les étale à pas égal entre le joueur et la cible ;
			-- la dernière s'arrête un peu avant la cible plutôt que de se superposer dessus.
			local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
			local distance = flat.Magnitude
			local direction = if distance > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
			local phase = (elapsed % CHASE_PERIOD) / CHASE_PERIOD
			local visibleCount = math.clamp(math.floor(distance / MIN_SPACING), 1, ARROW_COUNT)
			local pitch = distance / (visibleCount + 1)
			-- Chenillard calculé sur les flèches VISIBLES uniquement : sur un trajet court
			-- (peu de flèches allumées), indexer sur les 6 rangs comptait aussi les flèches
			-- masquées et la traînée affichée restait figée en sourdine au lieu de balayer.
			local lit = math.floor(phase * visibleCount)
			for i = 0, #worldArrows - 1 do
				local arrow = worldArrows[i + 1]
				-- Au-delà du nombre de flèches visibles pour cette distance → masquée.
				if i >= visibleCount then
					arrow.image.Visible = false
					continue
				end
				arrow.image.Visible = true
				local along = pitch * (i + 1)
				local _arg0 = direction * along
				local _exp = from + _arg0
				local _vector3 = Vector3.new(0, ARROW_HEIGHT, 0)
				local pos = _exp + _vector3
				arrow.part.Position = pos
				-- Chenillard : la flèche dont le rang correspond à la phase est pleine, les
				-- autres sont estompées.
				arrow.image.ImageTransparency = if i == lit then 0 else DIM_TRANSPARENCY
				-- Orientation écran : vers la flèche suivante (ou vers la cible pour la
				-- dernière visible).
				local isLast = i == visibleCount - 1
				local _result
				if isLast then
					_result = target
				else
					local _arg0_1 = pitch * (i + 2)
					local _arg0_2 = direction * _arg0_1
					local _exp_1 = from + _arg0_2
					local _vector3_1 = Vector3.new(0, ARROW_HEIGHT, 0)
					_result = _exp_1 + _vector3_1
				end
				local nextWorld = _result
				local here = camera:WorldToViewportPoint(pos)
				local nextPoint = camera:WorldToViewportPoint(nextWorld)
				arrow.image.Rotation = angleOf(Vector2.new(nextPoint.X - here.X, nextPoint.Y - here.Y))
			end
			-- Chevron de bord d'écran quand la cible n'est pas visible.
			local screen, onScreen = camera:WorldToViewportPoint(target)
			if onScreen then
				chev.Visible = false
			else
				local viewport = camera.ViewportSize
				local center = viewport * 0.5
				local toTarget = Vector2.new(screen.X - center.X, screen.Y - center.Y)
				local dir = if toTarget.Magnitude > 1 then toTarget.Unit else Vector2.new(0, -1)
				local margin = GUI_ARROW_SIZE
				local _vector2 = Vector2.new(math.clamp(dir.X * viewport.X, -center.X + margin, center.X - margin), math.clamp(dir.Y * viewport.Y, -center.Y + margin, center.Y - margin))
				local clamped = center + _vector2
				chev.Visible = true
				chev.Position = UDim2.new(0, clamped.X, 0, clamped.Y)
				chev.ImageTransparency = 0
				chev.Rotation = angleOf(dir)
			end
		end)
	end,
	pointAtGui = function(self, target)
		TutorialArrow:clear()
		local arrow = ensureGuiArrow()
		arrow.Visible = true
		renderConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local pos = target.AbsolutePosition
			local size = target.AbsoluteSize
			local bob = math.sin(elapsed * 4) * GUI_BOB
			-- À gauche du bord gauche, centrée verticalement, pointant vers la droite (90°).
			arrow.Position = UDim2.new(0, pos.X - GUI_ARROW_GAP - GUI_ARROW_SIZE / 2 + bob, 0, pos.Y + size.Y / 2)
			arrow.Rotation = 90
		end)
	end,
	clear = function(self)
		stopRender()
		elapsed = 0
		for _, arrow in worldArrows do
			arrow.part:Destroy()
		end
		worldArrows = {}
		if chevron then
			chevron:Destroy()
			chevron = nil
		end
		if guiArrow then
			guiArrow:Destroy()
			guiArrow = nil
		end
	end,
}
return {
	TutorialArrow = TutorialArrow,
}
