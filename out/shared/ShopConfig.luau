-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local resistanceRiskParams = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ResistanceCurve").resistanceRiskParams
local SCROLL_MONEY_BOOST = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ScrollShopConfig").SCROLL_MONEY_BOOST
local _ShopBalance = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopBalance")
local BASE_CASH = _ShopBalance.BASE_CASH
local COMMUNITY = _ShopBalance.COMMUNITY
local MONEY_TIERS = _ShopBalance.MONEY_TIERS
local REBIRTH = _ShopBalance.REBIRTH
local RESISTANCE = _ShopBalance.RESISTANCE
local RESISTANCE_PASS = _ShopBalance.RESISTANCE_PASS
local ROCKET_SPEED = _ShopBalance.ROCKET_SPEED
-- ── Shop — structure + formulas ───────────────────────────────────────────────
-- Pure logic, no side effects. Imported by both the server (purchase authority)
-- and the client (display). Levels are the persisted source of truth
-- (PlayerProgressionService); the effective values and prices are *derived* from
-- the level here. All tunable numbers live in shared/ShopBalance.ts — edit there
-- to rebalance.
-- A stat is one upgradeable progression value. A shop button targets exactly one
-- stat (one button per stat for now — the BaseCash +5 button is disabled).
-- One per shop button under InGameUI/ShopMenu/Body.
-- Contexte passé au rendu d'une stat. `moneyMult` permet à BaseCash d'afficher le gain
-- EFFECTIF (multiplicateur de rebirth et boosts inclus) plutôt que la valeur brute :
-- après quelques rebirths, "1K → 1.2K" devient "512K → 614K".
local STATS = {
	BaseCash = {
		valueAttribute = "BaseCash",
		levelAttribute = "BaseCashLevel",
		startPrice = BASE_CASH.startPrice,
		priceGrowth = BASE_CASH.priceGrowth,
		valueFor = function(level)
			return math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ^ level)
		end,
		display = function(value, ctx)
			return `{FormatNumber(math.floor(value * ctx.moneyMult))}$`
		end,
	},
	RocketSpeed = {
		valueAttribute = "RocketSpeed",
		levelAttribute = "RocketSpeedLevel",
		startPrice = ROCKET_SPEED.startPrice,
		priceGrowth = ROCKET_SPEED.priceGrowth,
		firstLevelPrices = ROCKET_SPEED.firstLevelPrices,
		valueFor = function(level)
			return ROCKET_SPEED.baseValue + level
		end,
		display = function(value)
			return `{value}`
		end,
	},
	Resistance = {
		valueAttribute = "Resistance",
		levelAttribute = "ResistanceLevel",
		startPrice = RESISTANCE.startPrice,
		priceGrowth = RESISTANCE.priceGrowth,
		maxLevel = RESISTANCE.maxLevel,
		valueFor = function(level)
			return level
		end,
		display = function(value)
			return `{string.format("%.1f", resistanceRiskParams(value).safeWindow)}s`
		end,
	},
}
local ITEMS = {
	BaseCash = {
		id = "BaseCash",
		stat = "BaseCash",
		quantity = 1,
		frameName = "BButtonMoney",
		title = "Button money",
	},
	RocketSpeed = {
		id = "RocketSpeed",
		stat = "RocketSpeed",
		quantity = 1,
		frameName = "ARocketSpeed",
		title = "Rocket speed",
	},
	Resistance = {
		id = "Resistance",
		stat = "Resistance",
		quantity = 1,
		frameName = "DSafety",
		title = "Vol garanti",
	},
}
-- Iteration order for the client (matches the A/B/D frame ordering).
local ITEM_ORDER = { "RocketSpeed", "BaseCash", "Resistance" }
-- Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
-- serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix, et peut
-- imposer les prix de ses premiers niveaux (firstLevelPrices).
local function priceForLevel(stat, level)
	local cfg = STATS[stat]
	local _override = cfg.firstLevelPrices
	if _override ~= nil then
		_override = _override[level + 1]
	end
	local override = _override
	if override ~= nil then
		return override
	end
	return math.floor(cfg.startPrice * cfg.priceGrowth ^ level)
end
-- Total price to buy a whole item from `fromLevel` (strict sum of each level —
-- no bulk discount). For a +1 item this is just priceForLevel.
local function priceForItem(item, fromLevel)
	local total = 0
	do
		local i = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < item.quantity) then
				break
			end
			total += priceForLevel(item.stat, fromLevel + i)
		end
	end
	return total
end
-- True when the stat is at (or above) its cap and cannot be upgraded further.
local function isAtCap(stat, level)
	local max = STATS[stat].maxLevel
	return max ~= nil and level >= max
end
-- ── Rebirth pricing & reward (pure, shared client/server) ─────────────────────
-- Cash threshold required to perform rebirth number R+1 (R = rebirths already done).
local function rebirthCost(rebirths)
	local r = math.max(0, math.floor(rebirths))
	local override = REBIRTH.firstCosts[r + 1]
	if override ~= nil then
		return override
	end
	return math.floor(REBIRTH.baseCost * REBIRTH.costGrowth ^ r)
end
-- Multiplicateur d'argent permanent après `rebirths` rebirths. Géométrique : chaque
-- rebirth multiplie le précédent par REBIRTH.multGrowth.
local function rebirthMult(rebirths)
	local r = math.max(0, math.floor(rebirths))
	return REBIRTH.multGrowth ^ r
end
-- ── Multiplicateurs d'argent — rebirth multiplicatif, boosts additifs ────────────
-- Le rebirth MULTIPLIE ; la communauté et le palier de game-pass s'additionnent entre
-- eux dans un facteur de boost commun :
--   moneyMult = MultRebirth × (1 + (communauté − 1) + (palier − 1))
-- Conséquence voulue : un pass ×2 reste ×2 quel que soit le niveau de rebirth. Avec un
-- modèle purement additif, un MultRebirth de 4096 écraserait les paliers MONEY_TIERS
-- (un pass ×2 n'ajouterait plus que +1 sur 4096) et les rendrait invendables.
local function moneyMult(multRebirth, moneyTierMult, inCommunity, hasScrollBoost)
	if hasScrollBoost == nil then
		hasScrollBoost = false
	end
	local communityBonus = if inCommunity then COMMUNITY.mult - 1 else 0
	local tierBonus = moneyTierMult - 1
	-- Le ×1.25 acheté en ScrollToken (§6.27) rejoint les autres boosts DANS le facteur
	-- additif, pour la même raison qu'eux : multiplié par-dessus un MultRebirth énorme
	-- il resterait un vrai +25 %, mais additionné il ne peut pas écraser les game-passes.
	local scrollBonus = if hasScrollBoost then SCROLL_MONEY_BOOST.mult - 1 else 0
	return multRebirth * (1 + communityBonus + tierBonus + scrollBonus)
end
-- Effective resistance used by the risk loop: shop Resistance + the resistance
-- game pass (flat bonus levels), capped at the max level.
local function effectiveResistance(shopResistance, hasResistancePass)
	local total = shopResistance + (if hasResistancePass then RESISTANCE_PASS.addLevels else 0)
	return math.min(total, RESISTANCE.maxLevel)
end
-- The next money tier strictly above `currentMult` (for the shop upsell), or
-- undefined if already at the top. Tiers are a ladder — the highest owned wins.
local function nextMoneyTier(currentMult)
	for _, tier in MONEY_TIERS do
		if tier.mult > currentMult then
			return tier
		end
	end
	return nil
end
return {
	priceForLevel = priceForLevel,
	priceForItem = priceForItem,
	isAtCap = isAtCap,
	rebirthCost = rebirthCost,
	rebirthMult = rebirthMult,
	moneyMult = moneyMult,
	effectiveResistance = effectiveResistance,
	nextMoneyTier = nextMoneyTier,
	STATS = STATS,
	ITEMS = ITEMS,
	ITEM_ORDER = ITEM_ORDER,
}
