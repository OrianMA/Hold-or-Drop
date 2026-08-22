-- Compiled with roblox-ts v3.0.0
-- ── Boutique ScrollToken (BuyRewardBody) ──────────────────────────────────────
-- LE fichier de réglage des 6 achats payés en ScrollToken. Le prix écrit ici est
-- la seule source de vérité : le serveur le débite, le client l'affiche dans
-- `BuyButtonFrame/DisplayElementFrame/TextLabel`. Changer un prix ici le change
-- partout, sans retoucher Studio.
--
-- Les effets sont volontairement des VERBES connus du jeu (safe rebirth, +1 niveau
-- de stat, événement Mega Rocket) — la boutique ne crée aucune mécanique nouvelle,
-- elle en achète.
-- Le ×1.25 argent permanent. Additif comme les autres boosts d'argent (communauté,
-- game-passes) : il ajoute +0.25 au facteur de boosts, qui est ensuite multiplié par
-- MultRebirth — voir shared/ShopConfig.moneyMult et §6.6.
local SCROLL_MONEY_BOOST = {
	mult = 1.25,
	attribute = "ScrollMoneyBoost",
}
local SCROLL_SHOP_ITEMS = { {
	id = "SafeRebirth",
	frameName = "ASafeRebirth",
	price = 350_000,
	successText = "Safe rebirth  +1 Rebirth, progression kept",
}, {
	id = "MoneyMultiplier",
	frameName = "BMoneyMultiplier",
	price = 250_000,
	oneShot = true,
	successText = "1.25x Money unlocked  permanent",
}, {
	id = "MegaRocket",
	frameName = "CMegaRocket",
	price = 50_000,
}, {
	id = "RocketSpeed",
	frameName = "DRocketSpeed",
	price = 15_000,
	successText = "+1 Rocket speed",
}, {
	id = "BaseCash",
	frameName = "ERocketBaseCash",
	price = 20_000,
	successText = "+1 Base cash",
}, {
	id = "Resistance",
	frameName = "FRocketResistance",
	price = 25_000,
	successText = "+1 Resistance",
} }
local function scrollShopItem(id)
	for _, item in SCROLL_SHOP_ITEMS do
		if item.id == id then
			return item
		end
	end
	return nil
end
-- Bandeau serveur-large quand un joueur paie l'événement Mega Rocket.
local function megaRocketPurchaseAnnounce(playerName)
	return `{playerName} triggered the MEGA ROCKET  CASH ×8`
end
return {
	scrollShopItem = scrollShopItem,
	megaRocketPurchaseAnnounce = megaRocketPurchaseAnnounce,
	SCROLL_MONEY_BOOST = SCROLL_MONEY_BOOST,
	SCROLL_SHOP_ITEMS = SCROLL_SHOP_ITEMS,
}
