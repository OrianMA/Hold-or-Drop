-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local _ScrollShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig")
local SCROLL_SHOP_ITEMS = _ScrollShopConfig.SCROLL_SHOP_ITEMS
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
local player = Players.LocalPlayer
-- Anti double-clic. Ne protège que de la répétition immédiate : la vraie garde est
-- serveur.
local CLICK_DEBOUNCE = 0.4
local SUCCESS_COLOR = Color3.new(1, 0.85, 0.35)
-- Résout une carte. FindFirstChild partout (jamais WaitForChild) : une Frame absente
-- ou renommée coûte UNE carte, pas le blocage de tous les init clients suivants.
local function readCard(scrollingFrame, item)
	local frame = scrollingFrame:FindFirstChild(item.frameName)
	local _buyFrame = frame
	if _buyFrame ~= nil then
		_buyFrame = _buyFrame:FindFirstChild("BuyButtonFrame")
	end
	local buyFrame = _buyFrame
	local _priceText = buyFrame
	if _priceText ~= nil then
		_priceText = _priceText:FindFirstChild("DisplayElementFrame")
		if _priceText ~= nil then
			_priceText = _priceText:FindFirstChild("TextLabel")
		end
	end
	local priceText = _priceText
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
	return {
		item = item,
		priceText = priceText,
		button = button,
	}
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
	local lastClick = 0
	for _, card in cards do
		-- Le prix affiché vient TOUJOURS de la config, jamais du texte posé en Studio.
		card.priceText.Text = FormatNumber(card.item.price)
		card.button.Activated:Connect(function()
			local now = os.clock()
			if now - lastClick < CLICK_DEBOUNCE then
				return nil
			end
			lastClick = now
			Events.ScrollShopPurchaseEvent:FireServer(card.item.id)
		end)
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
