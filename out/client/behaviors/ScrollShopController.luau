-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local _ScrollShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig")
local SCROLL_SHOP_ITEMS = _ScrollShopConfig.SCROLL_SHOP_ITEMS
local SCROLL_SHOP_OWNED_LABEL = _ScrollShopConfig.SCROLL_SHOP_OWNED_LABEL
local scrollShopItem = _ScrollShopConfig.scrollShopItem
local ScrollTokenDisplay = TS.import(script, script.Parent.Parent, "ui", "ScrollTokenDisplay").ScrollTokenDisplay
local InformationText = TS.import(script, script.Parent.Parent, "ui", "InformationText").InformationText
-- Boutique ScrollToken (QuestsPanel/BuyRewardBody) — le pendant client de
-- ScrollShopService. Deux responsabilités, rien de plus :
--   • écrire le PRIX de chaque carte depuis shared/ScrollShopConfig, pour qu'un
--     changement de prix se voie sans retoucher Studio ;
--   • envoyer l'intention d'achat et jouer le retour visuel quand le serveur confirme.
--
-- L'achat est immédiat (pas de confirmation) : le serveur revalide solde, unicité et
-- plafond, débite, applique l'effet, puis répond par ScrollShopPurchasedEvent. Un
-- refus arrive en bandeau rouge via InformationTextEvent — il n'y a donc AUCUNE
-- pré-validation ici : le client ne connaît pas les règles, il ne les devine pas.
--
-- Seule exception, purement visuelle : un objet à ACHAT UNIQUE déjà acquis affiche
-- CLAIM à la place de son prix (et masque l'icône de token à côté). L'état vient de
-- l'attribut répliqué déclaré par l'objet (`ownedAttribute`), donc l'affichage suit
-- l'achat sans aller-retour et est correct dès la connexion.
local player = Players.LocalPlayer
-- Anti double-clic. Ne protège que de la répétition immédiate : la vraie garde est
-- serveur.
local CLICK_DEBOUNCE = 0.4
local SUCCESS_COLOR = Color3.new(1, 0.85, 0.35)
-- Objet à achat unique déjà acquis ? Lit l'attribut que l'objet déclare lui-même.
local function isOwned(item)
	if item.ownedAttribute == nil then
		return false
	end
	local _condition = (player:GetAttribute(item.ownedAttribute))
	if _condition == nil then
		_condition = 0
	end
	return _condition > 0
end
-- Résout une carte. FindFirstChild partout (jamais WaitForChild) : une Frame absente
-- ou renommée coûte UNE carte, pas le blocage de tous les init clients suivants.
local function readCard(scrollingFrame, item)
	local frame = scrollingFrame:FindFirstChild(item.frameName)
	local _buyFrame = frame
	if _buyFrame ~= nil then
		_buyFrame = _buyFrame:FindFirstChild("BuyButtonFrame")
	end
	local buyFrame = _buyFrame
	local _displayFrame = buyFrame
	if _displayFrame ~= nil then
		_displayFrame = _displayFrame:FindFirstChild("DisplayElementFrame")
	end
	local displayFrame = _displayFrame
	local _priceText = displayFrame
	if _priceText ~= nil then
		_priceText = _priceText:FindFirstChild("TextLabel")
	end
	local priceText = _priceText
	local _priceIcon = displayFrame
	if _priceIcon ~= nil then
		_priceIcon = _priceIcon:FindFirstChild("ScrollTokenImage")
	end
	local priceIcon = _priceIcon
	local _button = buyFrame
	if _button ~= nil then
		_button = _button:FindFirstChild("TextButton")
	end
	local button = _button
	local _result = priceText
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	local _condition = not _result
	if not _condition then
		local _result_1 = button
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("GuiButton")
		end
		_condition = not _result_1
	end
	if _condition then
		warn(`ScrollShopController: {item.frameName} incomplet — objet {item.id} non branché`)
		return nil
	end
	local _object = {
		item = item,
		priceText = priceText,
	}
	local _left = "priceIcon"
	local _result_1 = priceIcon
	if _result_1 ~= nil then
		_result_1 = _result_1:IsA("GuiObject")
	end
	_object[_left] = if _result_1 then priceIcon else nil
	_object.button = button
	return _object
end
local function init()
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local body = inGameUI:WaitForChild("QuestsPanel"):WaitForChild("BuyRewardBody")
	local scrollingFrame = body:WaitForChild("ScrollingFrame")
	local cards = {}
	for _, item in SCROLL_SHOP_ITEMS do
		local card = readCard(scrollingFrame, item)
		if card then
			table.insert(cards, card)
		end
	end
	-- Le prix affiché vient TOUJOURS de la config, jamais du texte posé en Studio —
	-- sauf pour un achat unique déjà acquis, qui affiche CLAIM sans son icône.
	local renderCard = function(card)
		local owned = isOwned(card.item)
		card.priceText.Text = if owned then SCROLL_SHOP_OWNED_LABEL else FormatNumber(card.item.price)
		if card.priceIcon then
			card.priceIcon.Visible = not owned
		end
	end
	local lastClick = 0
	for _, card in cards do
		renderCard(card)
		card.button.Activated:Connect(function()
			-- Déjà acquis : le serveur refuserait de toute façon, autant ne pas lui
			-- envoyer un achat impossible ni faire clignoter un bandeau de refus.
			if isOwned(card.item) then
				return nil
			end
			local now = os.clock()
			if now - lastClick < CLICK_DEBOUNCE then
				return nil
			end
			lastClick = now
			Events.ScrollShopPurchaseEvent:FireServer(card.item.id)
		end)
		-- L'attribut de possession est répliqué : la carte bascule sur CLAIM dès que le
		-- serveur l'a posé, sans que l'achat ait besoin de la prévenir.
		if card.item.ownedAttribute ~= nil then
			player:GetAttributeChangedSignal(card.item.ownedAttribute):Connect(function()
				return renderCard(card)
			end)
		end
	end
	-- Achat confirmé : les tokens sont déjà débités côté serveur et l'attribut a déjà
	-- bougé — il ne reste que la lecture de la dépense et le bandeau de l'objet.
	-- Le Mega Rocket n'a pas de bandeau propre : il diffuse déjà le sien à tout le
	-- serveur (§6.24), en dire plus ferait doublon.
	Events.ScrollShopPurchasedEvent.OnClientEvent:Connect(function(id, price)
		ScrollTokenDisplay:spend(price)
		local item = scrollShopItem(id)
		local _result = item
		if _result ~= nil then
			_result = _result.successText
		end
		if _result ~= nil then
			InformationText:show(item.successText, {
				rarity = "Rare",
				color = SUCCESS_COLOR,
			})
		end
	end)
end
return {
	init = init,
}
