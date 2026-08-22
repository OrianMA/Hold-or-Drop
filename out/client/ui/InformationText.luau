-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Bandeaux d'information du HUD, empilables.
--
-- InGameUI/InformationTextCanvasGroup est un simple CONTENEUR (UIListLayout
-- vertical) : chaque message clone le template `InformationEntry` et s'ajoute
-- SOUS le précédent, avec son propre fondu. Plusieurs messages peuvent donc
-- vivre en même temps.
--
--   InformationText.show("Finish");
--   InformationText.show("Pas assez d'argent", { color: DENIED_COLOR });
--   InformationText.show("Nouveau record !", { rarity: "Epic" });
--
-- Chaque rareté a sa hauteur (le texte est TextScaled → la hauteur pilote la
-- taille), son gradient et son son. Legendary utilise un TextLabel dédié
-- (LegendaryText) qui embarque le script RainbowText.
local FADE_IN_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Durée d'affichage historique du flash "Finish" de fin de partie : elle SÉQUENCE
-- l'animation de paiement (EndGameAnimation attend FADE_IN + ce hold avant de
-- lancer la descente du multiplicateur), donc elle ne suit PAS les durées
-- confortables des bandeaux ci-dessous — l'appelant la passe explicitement.
local FINISH_HOLD = 0.2
local DEFAULT_COLOR = Color3.new(1, 1, 1)
local CANVAS_NAME = "InformationTextCanvasGroup"
-- Le conteneur des bandeaux est un FRÈRE des popups sous InGameUI, qui est en
-- ZIndexBehavior.Sibling : à ZIndex égal, c'est l'ordre dans l'Explorer qui tranche,
-- et QuestsPanel (comme les autres popups) passait donc DEVANT le bandeau. Un
-- message qui explique pourquoi un achat vient d'être refusé doit toujours être
-- lisible, y compris par-dessus le menu qui l'a déclenché : on le force au-dessus de
-- tout (le plus haut ZIndex authoré ailleurs est 10, sur RocketLaunch).
local CANVAS_Z_INDEX = 50
local TEMPLATE_NAME = "InformationEntry"
local LABEL_NAME = "InformationText"
local LEGENDARY_LABEL_NAME = "LegendaryText"
local RAINBOW_SCRIPT_NAME = "RainbowText"
-- Au-delà, le plus ancien bandeau est retiré instantanément : l'écran ne se
-- remplit jamais de messages.
local MAX_ENTRIES = 5
-- ── Descente pendant un vol ───────────────────────────────────────────────────
-- Position Y (fraction d'écran) du HAUT de la pile pendant un vol. Le HUD de vol
-- pose son gros MultiplierText en haut-centre (0.08 → 0.21 de l'écran), pile là
-- où les bandeaux s'empilent : ils descendent donc sous lui le temps du vol, puis
-- remontent à leur position Studio. `setInFlight` est piloté par
-- RocketLaunchBehavior (décollage / fin de partie).
local IN_FLIGHT_Y = 0.24
local MOVE_TI = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STYLES = {
	Common = {
		height = 0.08,
		hold = 5,
	},
	Rare = {
		height = 0.09,
		hold = 5,
		gradient = "RareGradient",
		sound = AudioConfig.sfx.information,
	},
	Epic = {
		height = 0.1,
		hold = 5,
		gradient = "EpicGradient",
		sound = AudioConfig.sfx.information,
	},
	Legendary = {
		height = 0.12,
		hold = 6.5,
		legendary = true,
		sound = AudioConfig.sfx.informationLegendary,
	},
}
local GRADIENT_NAMES = { "CommonGradient", "RareGradient", "EpicGradient" }
-- ── Sons ──────────────────────────────────────────────────────────────────────
-- Templates persistants en SoundService (même approche que UiClickSound) :
-- l'asset reste en mémoire et les clones peuvent se chevaucher.
local soundTemplates = {}
local function playSound(def)
	local _id = def.id
	local template = soundTemplates[_id]
	if not template then
		template = Instance.new("Sound")
		template.Name = "InformationTextTemplate"
		template.SoundId = def.id
		template.Volume = def.volume
		template.Parent = SoundService
		local _id_1 = def.id
		local _template = template
		soundTemplates[_id_1] = _template
	end
	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
end
-- ── Références GUI ────────────────────────────────────────────────────────────
local cachedCanvas
-- Position authored en Studio, capturée au premier appel de setInFlight (donc
-- avant tout déplacement) : c'est celle qu'on restaure en fin de vol.
local authoredPosition
local moveTween
local function findCanvas()
	if cachedCanvas and cachedCanvas.Parent ~= nil then
		return cachedCanvas
	end
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end
	for _, desc in gui:GetDescendants() do
		if desc.Name == CANVAS_NAME and desc:IsA("CanvasGroup") then
			desc.ZIndex = CANVAS_Z_INDEX
			cachedCanvas = desc
			return desc
		end
	end
	return nil
end
local function findTemplate(canvas)
	local found = canvas:FindFirstChild(TEMPLATE_NAME)
	return if found ~= nil and found:IsA("CanvasGroup") then found else nil
end
local function findLabel(entry, name)
	local found = entry:FindFirstChild(name, true)
	return if found ~= nil and found:IsA("TextLabel") then found else nil
end
-- Les hauteurs de STYLES sont en fraction d'écran, mais une entrée est
-- dimensionnée par rapport au conteneur (qui n'occupe qu'une tranche de
-- l'écran) : on convertit à la volée pour rester juste même si le conteneur est
-- redimensionné en Studio.
local function entryHeightScale(canvas, screenFraction)
	local containerScale = canvas.Size.Y.Scale
	if containerScale <= 0 then
		return screenFraction
	end
	return screenFraction / containerScale
end
-- ── Pile active ───────────────────────────────────────────────────────────────
local active = {}
local nextLayoutOrder = 0
local nextToken = 0
local function removeEntry(entry)
	if entry.token == -1 then
		return nil
	end
	entry.token = -1
	for _, t in entry.tweens do
		t:Cancel()
	end
	local _entry = entry
	local index = (table.find(active, _entry) or 0) - 1
	if index >= 0 then
		table.remove(active, index + 1)
	end
	entry.instance:Destroy()
end
local InformationText = {
	FADE_IN_TIME = FADE_IN_TI.Time,
	HOLD_TIME = FINISH_HOLD,
	FADE_OUT_TIME = FADE_OUT_TI.Time,
	setInFlight = function(self, inFlight)
		local canvas = findCanvas()
		if not canvas then
			return nil
		end
		if authoredPosition == nil then
			authoredPosition = canvas.Position
		end
		local target = if inFlight then UDim2.new(authoredPosition.X.Scale, authoredPosition.X.Offset, IN_FLIGHT_Y, 0) else authoredPosition
		if moveTween then
			moveTween:Cancel()
		end
		moveTween = TweenService:Create(canvas, MOVE_TI, {
			Position = target,
		})
		moveTween:Play()
	end,
	hide = function(self)
		local _array = {}
		local _length = #_array
		table.move(active, 1, #active, _length + 1, _array)
		for _, entry in _array do
			removeEntry(entry)
		end
	end,
	show = function(self, text, options)
		local canvas = findCanvas()
		if not canvas then
			warn(`InformationText: {CANVAS_NAME} introuvable sous PlayerGui`)
			return nil
		end
		local template = findTemplate(canvas)
		if not template then
			warn(`InformationText: template {TEMPLATE_NAME} introuvable sous {CANVAS_NAME}`)
			return nil
		end
		local _result = options
		if _result ~= nil then
			_result = _result.rarity
		end
		local _condition = _result
		if _condition == nil then
			_condition = "Common"
		end
		local rarity = _condition
		local style = STYLES[rarity]
		local isLegendary = style.legendary == true
		while #active >= MAX_ENTRIES do
			removeEntry(active[1])
		end
		local instance = template:Clone()
		instance.Name = `{TEMPLATE_NAME}_{rarity}`
		instance.Size = UDim2.fromScale(1, entryHeightScale(canvas, style.height))
		instance.GroupTransparency = 1
		-- Ordre croissant : le nouveau bandeau se place SOUS le plus récent.
		instance.LayoutOrder = nextLayoutOrder
		nextLayoutOrder += 1
		local normalLabel = findLabel(instance, LABEL_NAME)
		local legendaryLabel = findLabel(instance, LEGENDARY_LABEL_NAME)
		if normalLabel then
			normalLabel.Visible = not isLegendary
		end
		if legendaryLabel then
			legendaryLabel.Visible = isLegendary
			-- Le script arc-en-ciel est désactivé dans le template : il ne tourne
			-- que sur les bandeaux Legendary (une boucle par bandeau affiché).
			local rainbow = legendaryLabel:FindFirstChild(RAINBOW_SCRIPT_NAME)
			if rainbow ~= nil and rainbow:IsA("LocalScript") then
				rainbow.Enabled = isLegendary
			end
		end
		local label = if isLegendary then legendaryLabel else normalLabel
		if label then
			label.Text = text
			-- En Legendary la couleur est pilotée par le script RainbowText.
			if not isLegendary then
				local _result_1 = options
				if _result_1 ~= nil then
					_result_1 = _result_1.color
				end
				local _condition_1 = _result_1
				if _condition_1 == nil then
					_condition_1 = DEFAULT_COLOR
				end
				label.TextColor3 = _condition_1
			end
			for _, name in GRADIENT_NAMES do
				local gradient = label:FindFirstChild(name)
				if gradient ~= nil and gradient:IsA("UIGradient") then
					gradient.Enabled = name == style.gradient
				end
			end
		end
		instance.Visible = true
		instance.Parent = canvas
		nextToken += 1
		local entry = {
			instance = instance,
			tweens = {},
			token = nextToken,
		}
		local myToken = entry.token
		table.insert(active, entry)
		if style.sound then
			playSound(style.sound)
		end
		local fadeIn = TweenService:Create(instance, FADE_IN_TI, {
			GroupTransparency = 0,
		})
		local _exp = entry.tweens
		table.insert(_exp, fadeIn)
		fadeIn:Play()
		local _result_1 = options
		if _result_1 ~= nil then
			_result_1 = _result_1.holdSeconds
		end
		local _condition_1 = _result_1
		if _condition_1 == nil then
			_condition_1 = style.hold
		end
		local hold = _condition_1
		task.delay(FADE_IN_TI.Time + hold, function()
			if entry.token ~= myToken then
				return nil
			end
			local fadeOut = TweenService:Create(instance, FADE_OUT_TI, {
				GroupTransparency = 1,
			})
			local _exp_1 = entry.tweens
			table.insert(_exp_1, fadeOut)
			fadeOut.Completed:Connect(function()
				return removeEntry(entry)
			end)
			fadeOut:Play()
		end)
	end,
}
local function init()
	Events.InformationTextEvent.OnClientEvent:Connect(function(text, options)
		InformationText:show(text, options)
	end)
end
return {
	init = init,
	InformationText = InformationText,
}
