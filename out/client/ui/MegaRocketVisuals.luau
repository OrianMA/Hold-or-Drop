-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local CollectionService = _services.CollectionService
local RunService = _services.RunService
local _MegaRocketConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MegaRocketConfig")
local MEGA_ROCKET_PANEL_TAG = _MegaRocketConfig.MEGA_ROCKET_PANEL_TAG
local MEGA_ROCKET_TAG = _MegaRocketConfig.MEGA_ROCKET_TAG
-- Arc-en-ciel des Mega Rockets (§6.24) — 100 % présentation, donc 100 % client.
--
-- Le serveur se contente de poser le tag MEGA_ROCKET_TAG sur le modèle `Rocket`
-- (RocketPlacer) ; ici on passe ses parts en Neon et on fait défiler leur teinte.
-- « Ses parts » = TOUT ce qui descend du modèle et est visible : Part, WedgePart,
-- MeshPart, UnionOperation (celles-ci ont besoin de UsePartColor, voir addPart).
-- Les templates n'ont ni SurfaceAppearance ni TextureID ni Decal, et leurs
-- SpecialMesh ont un VertexColor neutre — Color s'applique donc partout.
-- Chaque part reçoit un décalage de teinte proportionnel à sa hauteur DANS la
-- fusée (mesuré une fois, sur le pad) : le dégradé balaie donc la fusée du bas
-- vers le haut au lieu de la faire clignoter d'un bloc.
--
-- Le fond du panneau d'événement (MegaRocketFrame, tagué MEGA_ROCKET_PANEL_TAG en
-- Studio) porte le même arc-en-ciel, mais en DÉGRADÉ QUI DÉFILE : un UIGradient
-- dont la ColorSequence est reconstruite à chaque frame avec la phase courante.
-- Un aplat qui change de teinte ne rendrait pas la même chose — c'est le défilement
-- qui fait l'effet. Le panneau s'anime en permanence : le compte à rebours est
-- toujours affiché.
--
-- Une seule connexion RenderStepped, ouverte dès qu'il y a quelque chose à animer
-- (panneau OU fusée) et fermée quand il n'y a plus rien (même approche que
-- MoneyBurst §6.21). Avec StreamingEnabled seuls les objets à portée existent côté
-- client, donc la boucle reste minuscule.
local CYCLE_TIME = 2.5
local HUE_PER_STUD = 0.045
local UPDATE_INTERVAL = 1 / 20
-- Luminosité (V du HSV) des couleurs posées. Le Neon brille PROPORTIONNELLEMENT à
-- la luminosité de sa couleur : à 1 la fusée est un bloc de lumière blanchi par le
-- bloom et les arêtes disparaissent. En dessous de 1 il ne reste qu'un glow coloré
-- et la silhouette redevient nette. C'est LE bouton pour doser l'effet.
local NEON_VALUE = 0.7
-- ── Panneau ───────────────────────────────────────────────────────────────────
-- Le fond du panneau est une GuiObject, pas du Neon : pas de bloom à contenir, donc
-- couleurs pleines (V = 1) comme la référence.
local PANEL_VALUE = 1
-- Durée d'un tour complet du dégradé. Le panneau a sa PROPRE horloge : il défile
-- nettement plus vite que la teinte des fusées (CYCLE_TIME), c'est ce qui donne le
-- mouvement de bandeau.
local PANEL_CYCLE_TIME = 1.5
-- Points de la ColorSequence étalés sur la largeur (max Roblox : 20). 16 suffit pour
-- que le dégradé paraisse continu.
local PANEL_STOPS = 16
local PANEL_GRADIENT_NAME = "RainbowGradient"
local rockets = {}
-- Le dégradé posé sur le fond du compte à rebours
-- (Workspace/.../SurfaceGui/MegaRocketFrame).
local panelGradient
local stepConn
local elapsed = 0
local sinceUpdate = 0
local function addPart(entry, part)
	-- Une part invisible (helpers, colliders) n'a rien à colorer — autant l'exclure
	-- de la boucle : les fusées de haut niveau ont plus de 120 parts.
	if part.Transparency >= 1 then
		return nil
	end
	-- Une UnionOperation garde par défaut les couleurs des formes qui la composent
	-- et IGNORE sa propre propriété Color — sans ça les unions (coque de Lvl1/2/3)
	-- resteraient grises au milieu de l'arc-en-ciel.
	if part:IsA("UnionOperation") then
		part.UsePartColor = true
	end
	local _parts = entry.parts
	local _part = part
	local _arg1 = (part.Position.Y - entry.baseY) * HUE_PER_STUD
	_parts[_part] = _arg1
	part.Material = Enum.Material.Neon
end
local refreshLoop
local function track(instance)
	local _condition = not instance:IsA("Model")
	if not _condition then
		local _instance = instance
		_condition = rockets[_instance] ~= nil
	end
	if _condition then
		return nil
	end
	local model = instance
	local entry
	entry = {
		parts = {},
		baseY = model:GetPivot().Position.Y,
		descendantConn = model.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				addPart(entry, d)
			end
		end),
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			addPart(entry, d)
		end
	end
	rockets[model] = entry
	refreshLoop()
end
local function untrack(instance)
	local _instance = instance
	local entry = rockets[_instance]
	if not entry then
		return nil
	end
	entry.descendantConn:Disconnect()
	local _instance_1 = instance
	rockets[_instance_1] = nil
	refreshLoop()
end
-- Un arc-en-ciel COMPLET étalé sur la largeur, décalé de `phase`. Les teintes
-- décroissent de gauche à droite (comme la référence) et le motif couvre pile un
-- tour, donc il défile sans couture visible.
local function rainbowSequence(phase)
	local stops = {}
	for i = 0, PANEL_STOPS - 1 do
		local t = i / (PANEL_STOPS - 1)
		-- Le modulo de Luau suit le signe du diviseur : (phase - t) % 1 reste positif.
		local _colorSequenceKeypoint = ColorSequenceKeypoint.new(t, Color3.fromHSV((phase - t) % 1, 1, PANEL_VALUE))
		table.insert(stops, _colorSequenceKeypoint)
	end
	return ColorSequence.new(stops)
end
local function trackPanel(instance)
	if not instance:IsA("GuiObject") then
		return nil
	end
	-- Le UIGradient MULTIPLIE la couleur de fond : elle doit rester blanche pour que
	-- les teintes du dégradé sortent telles quelles.
	instance.BackgroundColor3 = Color3.new(1, 1, 1)
	-- Créé au besoin plutôt qu'exigé en Studio : c'est de la présentation pure et
	-- locale, autant que le panneau survive à une réédition du Frame.
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = PANEL_GRADIENT_NAME
		gradient.Parent = instance
	end
	panelGradient = gradient
	refreshLoop()
end
local function untrackPanel(instance)
	if panelGradient == nil or panelGradient.Parent ~= instance then
		return nil
	end
	panelGradient = nil
	refreshLoop()
end
-- Ouvre la boucle dès qu'il y a quelque chose à animer, la ferme sinon.
local start, stop
function refreshLoop()
	if not (next(rockets) == nil) or panelGradient ~= nil then
		start()
	else
		stop()
	end
end
function start()
	if stepConn then
		return nil
	end
	elapsed = 0
	sinceUpdate = 0
	stepConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		sinceUpdate += dt
		if sinceUpdate < UPDATE_INTERVAL then
			return nil
		end
		sinceUpdate = 0
		local base = elapsed / CYCLE_TIME
		-- Le dégradé du panneau défile sur sa propre horloge, plus rapide.
		if panelGradient then
			panelGradient.Color = rainbowSequence(elapsed / PANEL_CYCLE_TIME)
		end
		for _, entry in rockets do
			for part, offset in entry.parts do
				if not part.Parent then
					continue
				end
				part.Color = Color3.fromHSV((base + offset) % 1, 1, NEON_VALUE)
			end
		end
	end)
end
function stop()
	if not stepConn then
		return nil
	end
	stepConn:Disconnect()
	stepConn = nil
end
local function init()
	for _, instance in CollectionService:GetTagged(MEGA_ROCKET_TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(MEGA_ROCKET_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(MEGA_ROCKET_TAG):Connect(untrack)
	for _, instance in CollectionService:GetTagged(MEGA_ROCKET_PANEL_TAG) do
		trackPanel(instance)
	end
	CollectionService:GetInstanceAddedSignal(MEGA_ROCKET_PANEL_TAG):Connect(trackPanel)
	CollectionService:GetInstanceRemovedSignal(MEGA_ROCKET_PANEL_TAG):Connect(untrackPanel)
end
return {
	init = init,
}
