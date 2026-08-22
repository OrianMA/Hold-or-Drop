-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local isAtCap = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").isAtCap
local _ScrollShopConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig")
local SCROLL_MONEY_BOOST = _ScrollShopConfig.SCROLL_MONEY_BOOST
local megaRocketPurchaseAnnounce = _ScrollShopConfig.megaRocketPurchaseAnnounce
local scrollShopItem = _ScrollShopConfig.scrollShopItem
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local MegaRocketService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "MegaRocketService").MegaRocketService
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
-- Autorité de la boutique ScrollToken (§6.27) — le pendant de ShopService pour la
-- seconde monnaie. Même discipline : le client pré-affiche les prix pour un retour
-- immédiat, mais RIEN n'est décidé côté client. Ici on revalide le solde, l'unicité
-- et le plafond de stat, puis on débite et on applique l'effet.
--
-- Les effets ne sont que des appels aux systèmes existants (safe rebirth, +1 niveau,
-- événement Mega Rocket) : la boutique n'invente aucune mécanique.
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
local function deny(player, message)
	Events.InformationTextEvent:FireClient(player, message, {
		color = DENIED_COLOR,
	})
end
-- Objet à achat unique déjà acquis ? Lit l'attribut déclaré par l'objet lui-même.
local function isOwned(player, item)
	if item.ownedAttribute == nil then
		return false
	end
	return PlayerDataService:get(player, item.ownedAttribute) > 0
end
-- Applique l'effet. Retourne false quand l'achat doit être REFUSÉ (déjà possédé,
-- stat au plafond…) — le débit n'a alors pas lieu.
local function applyEffect(player, item)
	if item.id == "SafeRebirth" then
		-- Exactement le safe rebirth du produit Robux : +1 rebirth, aucun niveau perdu,
		-- argent intact (§6.9).
		PlayerProgressionService:safeRebirth(player)
		return true
	end
	if item.id == "MoneyMultiplier" then
		PlayerDataService:set(player, SCROLL_MONEY_BOOST.attribute, 1)
		-- Le boost entre dans MoneyMult / EffectiveBaseCash — il faut re-dériver tout de
		-- suite, sinon il ne s'appliquerait qu'à la prochaine recompute.
		PlayerProgressionService:recompute(player)
		return true
	end
	if item.id == "MegaRocket" then
		MegaRocketService:fireNow(megaRocketPurchaseAnnounce(player.DisplayName))
		return true
	end
	-- Les trois derniers sont des +1 niveau de stat, payés en tokens au lieu du cash.
	local stat = item.id
	if isAtCap(stat, PlayerProgressionService:getLevel(player, stat)) then
		deny(player, "Max level reached")
		return false
	end
	PlayerProgressionService:addLevel(player, stat, 1)
	return true
end
local function handlePurchase(player, itemId)
	local _itemId = itemId
	if not (type(_itemId) == "string") then
		return nil
	end
	local item = scrollShopItem(itemId)
	if not item then
		return nil
	end
	if isOwned(player, item) then
		deny(player, "Already owned")
		return nil
	end
	local balance = PlayerDataService:get(player, "ScrollTokens")
	if balance < item.price then
		deny(player, "Not enough tokens")
		return nil
	end
	-- L'effet passe AVANT le débit : un refus tardif (stat au plafond) ne doit jamais
	-- coûter de tokens au joueur.
	if not applyEffect(player, item) then
		return nil
	end
	PlayerDataService:add(player, "ScrollTokens", -item.price)
	Events.ScrollShopPurchasedEvent:FireClient(player, item.id, item.price)
	AnalyticsService:custom(player, "ScrollShopPurchase", item.price, item.id)
end
local ScrollShopService = {
	init = function(self)
		Events.ScrollShopPurchaseEvent.OnServerEvent:Connect(function(player, itemId)
			return handlePurchase(player, itemId)
		end)
	end,
}
return {
	ScrollShopService = ScrollShopService,
}
