-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
local _TutorialUI = TS.import(script, script.Parent, "TutorialUI")
local TutorialUI = _TutorialUI.TutorialUI
local Z_ARROW = _TutorialUI.Z_ARROW
-- Le pointage du tutorial. Deux modes :
--   • monde  → un RUBAN tendu des pieds du joueur JUSQU'À la cible : UNE seule part plate
--              dont un SurfaceGui tuile le chevron à taille fixe. Le ruban s'allonge ou se
--              rétracte avec la distance, les chevrons ne se déforment jamais, ils défilent
--              vers la cible. Il est tendu en 3D, pas à l'horizontale : son extrémité reste
--              posée sur l'objet, donc il plonge quand la cible est plus bas (saut) et monte
--              quand elle est plus haut. Plus un chevron de bord d'écran quand la cible est
--              hors champ (sinon le joueur ne sait pas où tourner).
--   • GUI    → une flèche à côté du rectangle de la cible, orientée vers elle.
-- Une seule boucle RenderStepped, active uniquement pendant un step qui pointe.
local ARROW_IMAGE = "rbxassetid://104204322044198"
-- --- Ruban monde ------------------------------------------------------------------
local TRAIL_WIDTH = 3.5
local TRAIL_TILE = 4
local TRAIL_PIXELS_PER_STUD = 24
local TRAIL_THICKNESS = 0.2
local TRAIL_START_OFFSET = 0
local TARGET_GROUND_PROBE = 60
local TARGET_GROUND_LIFT = 1.7
local TRAIL_MIN_LENGTH = 3
local SCROLL_PERIOD = 0.6
local TILE_PIXELS = TRAIL_TILE * TRAIL_PIXELS_PER_STUD
-- --- Flèches écran ----------------------------------------------------------------
local GUI_ARROW_SIZE = 64
local GUI_ARROW_GAP = 12
local GUI_BOB = 8
local trail
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
	image.ZIndex = Z_ARROW
	image.Parent = parent
	return image
end
local function makeTrail()
	-- Part support créée côté CLIENT : elle n'existe que pour ce joueur, donc aucune
	-- réplication ni gestion par joueur côté serveur.
	local part = Instance.new("Part")
	part.Name = "TutorialTrail"
	-- Repère LOCAL de la plaque : X = largeur, Y = longueur, Z = épaisseur. Elle est ensuite
	-- couchée à plat par son CFrame (voir layoutTrail).
	part.Size = Vector3.new(TRAIL_WIDTH, 1, TRAIL_THICKNESS)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = Workspace
	local surface = Instance.new("SurfaceGui")
	surface.Name = "TutorialTrailSurface"
	-- Face FRONT, pas Top : c'est la seule face dont l'orientation du GUI est garantie
	-- (haut du GUI = +Y de la part, jamais tournée ni miroir). Sur la face Top les axes du
	-- GUI sont transposés (X du GUI = Z de la part) — mesuré en Studio. On couche donc la
	-- plaque pour que sa face avant regarde le ciel et que son +Y vise la cible : la flèche,
	-- dessinée pointe en haut, pointe alors vers la cible sans hypothèse à vérifier.
	surface.Face = Enum.NormalId.Front
	-- PixelsPerStud FIXE : c'est ce qui garantit qu'un chevron mesure toujours TRAIL_TILE
	-- studs, que le ruban fasse 10 ou 90 studs de long. Seul leur NOMBRE change.
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = TRAIL_PIXELS_PER_STUD
	-- Pas d'AlwaysOnTop : le ruban se fait masquer par le décor comme n'importe quel objet.
	surface.LightInfluence = 0
	surface.Adornee = part
	surface.Parent = part
	-- L'image déborde d'une tuile pour pouvoir défiler sans laisser de trou : ce cadre la
	-- recoupe aux dimensions exactes du ruban.
	local clip = Instance.new("Frame")
	clip.Name = "TrailClip"
	clip.Size = UDim2.new(1, 0, 1, 0)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = surface
	local image = Instance.new("ImageLabel")
	image.Name = "TrailImage"
	image.Image = ARROW_IMAGE
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Tile
	-- Largeur : toute la largeur du ruban. Hauteur : une longueur FIXE en pixels, donc en
	-- studs (PixelsPerStud constant) — la tuile ne s'étire jamais.
	image.TileSize = UDim2.new(1, 0, 0, TILE_PIXELS)
	image.Size = UDim2.new(1, 0, 1, TILE_PIXELS)
	image.Position = UDim2.new(0, 0, 0, 0)
	image.Parent = clip
	return {
		part = part,
		surface = surface,
		image = image,
	}
end
local function ensureTrail()
	if trail and trail.part.Parent ~= nil then
		return trail
	end
	trail = makeTrail()
	return trail
end
local function ensureChevron()
	-- `Parent !== undefined` ne suffit PAS : un ScreenGui détruit (TutorialUI.destroy) garde
	-- sa hiérarchie interne intacte, juste détachée du DataModel — un chevron qui y est encore
	-- parenté a donc toujours un `Parent` non nil. Il faut vérifier qu'il est descendant du
	-- ScreenGui COURANT, sinon on continue d'écrire dans une instance orpheline.
	local gui = TutorialUI:ensure()
	if chevron and chevron:IsDescendantOf(gui) then
		return chevron
	end
	chevron = makeImage(gui, UDim2.new(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE))
	chevron.Name = "TutorialChevron"
	return chevron
end
local function ensureGuiArrow()
	-- Même piège que ensureChevron : un ScreenGui détruit garde un `Parent` non nil sur ses
	-- anciens enfants, donc on compare explicitement au ScreenGui courant plutôt que de tester
	-- juste la présence d'un parent.
	local gui = TutorialUI:ensure()
	if guiArrow and guiArrow:IsDescendantOf(gui) then
		return guiArrow
	end
	guiArrow = makeImage(gui, UDim2.new(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE))
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
local function characterRoot()
	local _hrp = Players.LocalPlayer.Character
	if _hrp ~= nil then
		_hrp = _hrp:FindFirstChild("HumanoidRootPart")
	end
	local hrp = _hrp
	local _result = hrp
	if _result ~= nil then
		_result = _result:IsA("BasePart")
	end
	return if _result then hrp else nil
end
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
-- Le groupe auquel appartient la cible : son Model s'il y en a un (ButtonModel), sinon son
-- dossier (Shop). Jamais le Workspace, ce qui reviendrait à exclure la scène entière.
local function targetGroup(part)
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		return model
	end
	local parent = part.Parent
	return if parent ~= nil and parent ~= Workspace then parent else part
end
-- Point visé : le SOL sous la cible, pas son centre — le ruban finit donc presque à plat
-- au pied de l'objet au lieu de s'arrêter en l'air à mi-hauteur. On part du dessous de la
-- cible et on sonde vers le bas. La demi-hauteur est mesurée dans le repère du MONDE — les
-- trois axes de la part projetés sur Y — et non via Size.Y, qui ne serait la verticale que
-- si la cible n'était pas tournée.
local function targetAimPoint(part)
	local cf = part.CFrame
	local size = part.Size
	local halfHeight = 0.5 * (math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z)
	local _position = part.Position
	local _vector3 = Vector3.new(0, halfHeight, 0)
	local base = _position - _vector3
	-- On exclut tout le GROUPE de la cible, pas seulement sa part : sinon la sonde s'arrête
	-- aussitôt sur le socle du bouton ou sur le mobilier de la boutique (mesuré : 0 stud de
	-- chute sous ButtonPart) et le ruban n'atteint jamais le sol. Le personnage et le ruban
	-- lui-même sont exclus pour la même raison.
	local excluded = { targetGroup(part) }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(excluded, character)
	end
	if trail then
		local _part = trail.part
		table.insert(excluded, _part)
	end
	groundParams.FilterDescendantsInstances = excluded
	local hit = Workspace:Raycast(base, Vector3.new(0, -TARGET_GROUND_PROBE, 0), groundParams)
	-- Sans sol trouvé (cible au-dessus du vide), on se rabat sur son pied.
	local _result
	if hit then
		local _position_1 = hit.Position
		local _vector3_1 = Vector3.new(0, TARGET_GROUND_LIFT, 0)
		_result = _position_1 + _vector3_1
	else
		_result = base
	end
	return _result
end
local TutorialArrow
TutorialArrow = {
	pointAtWorld = function(self, part)
		TutorialArrow:clear()
		renderConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			-- Le chevron vit dans le ScreenGui du tutorial, qui peut être détruit puis
			-- reconstruit pendant que cette boucle tourne : il doit être résolu ICI, à chaque
			-- frame, jamais capturé hors boucle — sinon on écrit dans une instance orpheline
			-- pendant que le vrai chevron reste invisible.
			local chev = ensureChevron()
			local ribbon = ensureTrail()
			local root = characterRoot()
			local target = targetAimPoint(part)
			-- La caméra doit être lue à chaque frame car elle est nil au spawn.
			local camera = Workspace.CurrentCamera
			if not root or not camera then
				ribbon.surface.Enabled = false
				chev.Visible = false
				return nil
			end
			-- Départ au TORSE du joueur (le HumanoidRootPart), arrivée au SOL sous la cible : le
			-- ruban est tendu en 3D, pas rabattu à l'horizontale. C'est ce qui fait qu'il plonge
			-- vers la cible quand le joueur saute, au lieu de monter avec lui en restant plat.
			local _position = root.Position
			local _vector3 = Vector3.new(0, TRAIL_START_OFFSET, 0)
			local start = _position + _vector3
			local span = target - start
			local length = span.Magnitude
			if length < TRAIL_MIN_LENGTH then
				-- Arrivé : plus rien à montrer, et à cette distance le ruban serait plus large
				-- que long.
				ribbon.surface.Enabled = false
			else
				ribbon.surface.Enabled = true
				local direction = span.Unit
				local _arg0 = span * 0.5
				local mid = start + _arg0
				-- Seules la LONGUEUR (Y local) et la position changent : largeur et épaisseur
				-- sont constantes, et PixelsPerStud étant fixe, allonger le ruban AJOUTE des
				-- chevrons au lieu de les étirer.
				ribbon.part.Size = Vector3.new(TRAIL_WIDTH, length, TRAIL_THICKNESS)
				-- Le +Y local — le haut du GUI — vise la cible. La largeur (X local) reste
				-- HORIZONTALE : la plaque bascule donc comme une rampe, mais ne roule jamais
				-- sur elle-même. Cible à la verticale = projection au sol nulle : largeur
				-- arbitraire, l'orientation n'a alors plus de sens de toute façon.
				local flat = Vector3.new(direction.X, 0, direction.Z)
				local side = if flat.Magnitude > 0.001 then Vector3.new(flat.Z, 0, -flat.X).Unit else Vector3.new(1, 0, 0)
				-- vZ = X × Y : la face avant (-Z), celle qui porte le GUI, regarde vers le haut,
				-- inclinée du même angle que le ruban.
				ribbon.part.CFrame = CFrame.fromMatrix(mid, side, direction, side:Cross(direction))
				-- Défilement : l'image fait une tuile de plus que le ruban et remonte d'une tuile
				-- par cycle, donc les chevrons avancent vers la cible sans trou ni saut.
				local phase = (elapsed % SCROLL_PERIOD) / SCROLL_PERIOD
				ribbon.image.Position = UDim2.new(0, 0, 0, -math.floor(phase * TILE_PIXELS))
			end
			-- Chevron de bord d'écran quand la cible n'est pas visible.
			local screen, onScreen = camera:WorldToViewportPoint(target)
			if onScreen then
				chev.Visible = false
			else
				local viewport = camera.ViewportSize
				local center = viewport * 0.5
				-- Z < 0 : la cible est DERRIÈRE la caméra, et WorldToViewportPoint renvoie alors des
				-- coordonnées écran en MIROIR — il faut inverser le vecteur, sinon le chevron indique
				-- exactement le mauvais côté (le cas même pour lequel il existe).
				local toTarget = Vector2.new(screen.X - center.X, screen.Y - center.Y)
				if screen.Z < 0 then
					toTarget = toTarget * (-1)
				end
				local dir = if toTarget.Magnitude > 1 then toTarget.Unit else Vector2.new(0, -1)
				local margin = GUI_ARROW_SIZE
				local _vector2 = Vector2.new(math.clamp(dir.X * viewport.X, -center.X + margin, center.X - margin), math.clamp(dir.Y * viewport.Y, -center.Y + margin, center.Y - margin))
				local clamped = center + _vector2
				chev.Visible = true
				-- `clamped` est en coordonnées VIEWPORT (origine sous la barre Roblox) et le
				-- chevron vit dans TutorialUI (origine en haut de l'écran) : même conversion
				-- que pour la flèche GUI, sinon le chevron est trop haut de l'inset.
				local chevOrigin = TutorialUI:originOffset()
				chev.Position = UDim2.new(0, clamped.X - chevOrigin.X, 0, clamped.Y - chevOrigin.Y)
				chev.ImageTransparency = 0
				chev.Rotation = angleOf(dir)
			end
		end)
	end,
	pointAtGui = function(self, target)
		TutorialArrow:clear()
		renderConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			-- Même piège que le chevron : cette flèche vit dans le ScreenGui du tutorial, qui
			-- peut être détruit puis reconstruit pendant que la boucle tourne. On la résout ICI,
			-- à chaque frame, plutôt que de la capturer hors boucle.
			local arrow = ensureGuiArrow()
			arrow.Visible = true
			-- La cible vit dans InGameUI, la flèche dans TutorialUI : deux ScreenGuis, deux
			-- repères (voir TutorialUI.originOffset). Sans cette conversion — la même que dans
			-- TutorialFocus.layoutDim — la flèche est décalée vers le haut de la hauteur de la
			-- barre Roblox et ne vise plus le milieu de la cible. Lu à chaque frame, jamais
			-- mis en cache : TutorialUI peut être reconstruit pendant que la boucle tourne.
			local origin = TutorialUI:originOffset()
			local pos = target.AbsolutePosition - origin
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
		if trail then
			trail.part:Destroy()
			trail = nil
		end
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
