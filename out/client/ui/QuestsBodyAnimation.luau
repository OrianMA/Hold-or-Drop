-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RunService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").RunService
-- Cascade d'ouverture d'un body du panneau des quêtes (QuestsBody / BuyRewardBody).
-- Rejouée à CHAQUE affichage — ouverture du panneau comme changement d'onglet — pour
-- que le passage d'un body à l'autre soit un vrai changement d'écran et pas une
-- substitution silencieuse.
--
-- Les éléments apparaissent l'un après l'autre en FONDU. Le fondu et pas un
-- glissement ou un pop d'échelle : les deux bodies sont pilotés par un layout
-- (UIListLayout / UIGridLayout) qui possède la position ET la taille de ses enfants,
-- donc toute animation de géométrie ferait re-couler la liste à chaque frame. La
-- transparence, elle, n'a aucun effet sur le layout.
--
-- Même discipline que DailyRewardsAnimation : les valeurs d'origine sont CAPTURÉES
-- au premier passage puis restaurées — rien n'est réécrit "en dur", donc retoucher
-- les transparences en Studio reste sans risque. Un compteur de génération invalide
-- une cascade abandonnée (changement d'onglet en plein fondu).
-- Durée du fondu d'UN élément, et décalage entre deux éléments consécutifs.
local FADE_DURATION = 0.22
local STAGGER = 0.035
-- Propriété de transparence capturée par instance, avec sa valeur d'origine.
-- Un état par body : la capture est faite une fois pour toutes.
local captured = {}
local running = {}
local function fadeProperties(instance, into)
	if instance:IsA("GuiObject") then
		local _into = into
		local _arg0 = {
			instance = instance,
			property = "BackgroundTransparency",
			original = instance.BackgroundTransparency,
		}
		table.insert(_into, _arg0)
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		local _into = into
		local _arg0 = {
			instance = instance,
			property = "TextTransparency",
			original = instance.TextTransparency,
		}
		table.insert(_into, _arg0)
	end
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		local _into = into
		local _arg0 = {
			instance = instance,
			property = "ImageTransparency",
			original = instance.ImageTransparency,
		}
		table.insert(_into, _arg0)
	end
	if instance:IsA("UIStroke") then
		local _into = into
		local _arg0 = {
			instance = instance,
			property = "Transparency",
			original = instance.Transparency,
		}
		table.insert(_into, _arg0)
	end
end
-- Les deux layouts trient par NOM (SortOrder.Name), donc l'ordre alphabétique EST
-- l'ordre visuel — inutile de lire des positions absolues, qui ne seraient de toute
-- façon pas encore calculées au moment où le body s'affiche.
local function elementsOf(body)
	local _body = body
	local found = captured[_body]
	if found then
		return found
	end
	local scrollingFrame = body:FindFirstChild("ScrollingFrame")
	local elements = {}
	if not scrollingFrame then
		local _body_1 = body
		captured[_body_1] = elements
		return elements
	end
	local children = {}
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(children, child)
		end
	end
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	for i = 0, #children - 1 do
		local fades = {}
		fadeProperties(children[i + 1], fades)
		for _, descendant in children[i + 1]:GetDescendants() do
			fadeProperties(descendant, fades)
		end
		local _arg0 = {
			fades = fades,
			delay = i * STAGGER,
		}
		table.insert(elements, _arg0)
	end
	local _body_1 = body
	captured[_body_1] = elements
	return elements
end
-- alpha 0 = invisible, 1 = valeur d'origine.
local function applyAlpha(element, alpha)
	for _, fade in element.fades do
		-- L'opacité d'origine est le PLANCHER : un élément déjà à 0.5 ne devient jamais
		-- plus opaque que 0.5.
		local value = fade.original + (1 - fade.original) * (1 - alpha);
		(fade.instance)[fade.property] = value
	end
end
local function stopLoop(body)
	local _body = body
	local connection = running[_body]
	if connection then
		connection:Disconnect()
		local _body_1 = body
		running[_body_1] = nil
	end
end
local QuestsBodyAnimation = {
	play = function(self, body)
		local elements = elementsOf(body)
		if #elements == 0 then
			return nil
		end
		stopLoop(body)
		for _, element in elements do
			applyAlpha(element, 0)
		end
		local last = elements[#elements]
		local total = last.delay + FADE_DURATION
		local elapsed = 0
		local connection = RunService.RenderStepped:Connect(function(delta)
			elapsed += delta
			for _, element in elements do
				local raw = math.clamp((elapsed - element.delay) / FADE_DURATION, 0, 1)
				-- Ease-out : l'élément prend sa pleine opacité vite puis se stabilise.
				applyAlpha(element, 1 - (1 - raw) * (1 - raw))
			end
			if elapsed >= total then
				stopLoop(body)
				for _, element in elements do
					applyAlpha(element, 1)
				end
			end
		end)
		local _body = body
		running[_body] = connection
	end,
	stop = function(self, body)
		stopLoop(body)
		local _body = body
		local elements = captured[_body]
		if not elements then
			return nil
		end
		for _, element in elements do
			applyAlpha(element, 1)
		end
	end,
}
return {
	QuestsBodyAnimation = QuestsBodyAnimation,
}
