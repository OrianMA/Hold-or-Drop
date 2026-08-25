-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local SCROLL_TOKENS_ATTR = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "QuestConfig").SCROLL_TOKENS_ATTR
local SCROLL_SHOP_ITEMS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig").SCROLL_SHOP_ITEMS
local _ShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig")
local STATS = _ShopConfig.STATS
local isAtCap = _ShopConfig.isAtCap
-- Pastille rouge « quelque chose est achetable dans la boutique ScrollToken »
-- (RedDotNotificationImage), affichée à deux endroits qui partagent le MÊME état :
--   • HUD/ButtonsFrame/QuestsFrame        → mène au panneau des quêtes
--   • QuestsPanel/ButtonsFrame/ShopFrame  → mène à l'onglet boutique
--
-- Règle d'affichage — la pastille est allumée tant qu'il reste un objet achetable
-- que le joueur n'a PAS encore vu. « Vu » veut dire : il a ouvert l'onglet boutique
-- pendant que cet objet était achetable (`acknowledge()`). Ouvrir la boutique éteint
-- donc la pastille même sans achat, et elle ne se rallume que quand un objet
-- DE PLUS devient achetable (typiquement parce que le solde de tokens a monté).
--
-- L'accusé de réception est un état CLIENT, en mémoire, volontairement non persisté :
-- à la reconnexion la pastille repart de zéro, ce qui est le bon défaut pour une
-- relance (et évite un champ sauvegardé + un RemoteEvent pour un simple point rouge).
--
-- « Achetable » reprend exactement les règles que le serveur appliquerait
-- (ScrollShopService) : solde suffisant, objet à achat unique pas déjà acquis,
-- stat pas au plafond. Sans ça la pastille pourrait pointer un achat refusé.
local player = Players.LocalPlayer
local DOT_NAME = "RedDotNotificationImage"
-- La pastille RESTE affichée ; seule la petite pulsation se rejoue, assez rarement
-- pour rappeler sans harceler.
local PULSE_INTERVAL = 40
-- Pulsation : une respiration lente + un balancement, pas une claque.
local PULSE_SCALE = 1.3
local PULSE_TILT = 12
local GROW = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SETTLE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local dots = {}
-- Objets achetables que le joueur a déjà vus. Sous-ensemble de l'ensemble achetable
-- courant : dès qu'un objet cesse d'être achetable il en sort, pour que le
-- redevenir (re-gagner des tokens après un achat) rallume bien la pastille.
local acknowledged = {}
local shown = false
local function tokens()
	local _condition = (player:GetAttribute(SCROLL_TOKENS_ATTR))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function attribute(name)
	local _condition = (player:GetAttribute(name))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
-- Les trois « +1 niveau de stat » de la boutique portent le nom de leur stat.
local function statFor(id)
	if id == "BaseCash" or id == "RocketSpeed" or id == "Resistance" then
		return id
	end
	return nil
end
local function isBuyable(item, balance)
	if balance < item.price then
		return false
	end
	if item.ownedAttribute ~= nil and attribute(item.ownedAttribute) > 0 then
		return false
	end
	local stat = statFor(item.id)
	if stat ~= nil and isAtCap(stat, attribute(STATS[stat].levelAttribute)) then
		return false
	end
	return true
end
local function animate(dot)
	dot.scale.Scale = 1
	dot.image.Rotation = dot.baseRotation
	TweenService:Create(dot.scale, GROW, {
		Scale = PULSE_SCALE,
	}):Play()
	TweenService:Create(dot.image, GROW, {
		Rotation = dot.baseRotation - PULSE_TILT,
	}):Play()
	task.wait(GROW.Time)
	TweenService:Create(dot.image, SWING, {
		Rotation = dot.baseRotation + PULSE_TILT,
	}):Play()
	task.wait(SWING.Time)
	TweenService:Create(dot.image, SWING, {
		Rotation = dot.baseRotation,
	}):Play()
	TweenService:Create(dot.scale, SETTLE, {
		Scale = 1,
	}):Play()
end
local function pulse()
	for _, dot in dots do
		if dot.image.Visible then
			task.spawn(function()
				return animate(dot)
			end)
		end
	end
end
local function setShown(value)
	if shown == value then
		return nil
	end
	shown = value
	for _, dot in dots do
		dot.image.Visible = value
		if not value then
			dot.scale.Scale = 1
			dot.image.Rotation = dot.baseRotation
		end
	end
	-- Apparition : on pulse tout de suite, sinon le joueur peut attendre 40s avant le
	-- premier signe de vie.
	if value then
		pulse()
	end
end
local function refresh()
	local balance = tokens()
	local hasUnseen = false
	for _, item in SCROLL_SHOP_ITEMS do
		if isBuyable(item, balance) then
			local _id = item.id
			if not (acknowledged[_id] ~= nil) then
				hasUnseen = true
			end
		else
			local _id = item.id
			acknowledged[_id] = nil
		end
	end
	setShown(hasUnseen)
end
-- Résout une pastille. FindFirstChild partout : une pastille absente ou renommée ne
-- doit coûter que cet affichage, jamais le blocage des init clients suivants.
local function readDot(parent)
	local image = parent:FindFirstChild(DOT_NAME)
	local _result = image
	if _result ~= nil then
		_result = _result:IsA("GuiObject")
	end
	if not _result then
		warn(`ShopRedDot: {DOT_NAME} introuvable sous {parent:GetFullName()}`)
		return nil
	end
	local existing = image:FindFirstChildOfClass("UIScale")
	local scale
	if existing then
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Parent = image
	end
	scale.Scale = 1
	image.Visible = false
	local _arg0 = {
		image = image,
		scale = scale,
		baseRotation = image.Rotation,
	}
	table.insert(dots, _arg0)
end
local ShopRedDot = {
	init = function(self)
		local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
		local hudButtons = (inGameUI:WaitForChild("HUD")):WaitForChild("ButtonsFrame")
		readDot(hudButtons:WaitForChild("QuestsFrame"))
		local panelTabs = (inGameUI:WaitForChild("QuestsPanel")):WaitForChild("ButtonsFrame")
		readDot(panelTabs:WaitForChild("ShopFrame"))
		player:GetAttributeChangedSignal(SCROLL_TOKENS_ATTR):Connect(refresh)
		for _, item in SCROLL_SHOP_ITEMS do
			if item.ownedAttribute ~= nil then
				player:GetAttributeChangedSignal(item.ownedAttribute):Connect(refresh)
			end
		end
		for _, stat in { "BaseCash", "RocketSpeed", "Resistance" } do
			player:GetAttributeChangedSignal(STATS[stat].levelAttribute):Connect(refresh)
		end
		refresh()
		task.spawn(function()
			while true do
				task.wait(PULSE_INTERVAL)
				if shown then
					pulse()
				end
			end
		end)
	end,
	acknowledge = function(self)
		local balance = tokens()
		table.clear(acknowledged)
		for _, item in SCROLL_SHOP_ITEMS do
			if isBuyable(item, balance) then
				local _id = item.id
				acknowledged[_id] = true
			end
		end
		refresh()
	end,
}
return {
	ShopRedDot = ShopRedDot,
}
