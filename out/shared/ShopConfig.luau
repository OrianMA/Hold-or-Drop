-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
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
-- Up to 2 decimals, trailing zeros trimmed: 0.1, 2.65, 11.7. Mirrors the small
-- number rendering used by NumberFormat without flooring sub-1 values to "0".
local function trimDecimals(value)
	local hundredths = math.floor(value * 100 + 1e-7)
	if hundredths % 100 == 0 then
		return tostring(hundredths / 100)
	end
	if hundredths % 10 == 0 then
		return string.format("%.1f", hundredths / 100)
	end
	return string.format("%.2f", hundredths / 100)
end
local STATS = {
	BaseCash = {
		valueAttribute = "BaseCash",
		levelAttribute = "BaseCashLevel",
		startPrice = BASE_CASH.startPrice,
		priceGrowth = BASE_CASH.priceGrowth,
		valueFor = function(level)
			return math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ^ level)
		end,
		display = function(value)
			return FormatNumber(value)
		end,
	},
	RocketSpeed = {
		valueAttribute = "RocketSpeed",
		levelAttribute = "RocketSpeedLevel",
		startPrice = ROCKET_SPEED.startPrice,
		priceGrowth = ROCKET_SPEED.priceGrowth,
		valueFor = function(level)
			return ROCKET_SPEED.baseValue + level
		end,
		display = function(value)
			return tostring(value)
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
			return tostring(value)
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
		title = "Resistance",
	},
}
-- Iteration order for the client (matches the A/B/D frame ordering).
local ITEM_ORDER = { "RocketSpeed", "BaseCash", "Resistance" }
-- Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
-- serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix.
local function priceForLevel(stat, level)
	local cfg = STATS[stat]
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
	return math.floor(REBIRTH.baseCost * REBIRTH.costGrowth ^ r)
end
-- Permanent money multiplier after `rebirths` rebirths. Table for the designed
-- early curve, then a constant linear queue (+multTail per extra rebirth).
local function rebirthMult(rebirths)
	local r = math.max(0, math.floor(rebirths))
	local multTable = REBIRTH.multTable
	local lastIndex = #multTable - 1
	if r <= lastIndex then
		return multTable[r + 1]
	end
	return multTable[lastIndex + 1] + (r - lastIndex) * REBIRTH.multTail
end
-- ── Money multipliers — additive bonus model (pure, shared client/server) ──────
-- ADDITIVE: each "×N" factor contributes "+(N-1)", so a lone factor keeps its
-- labelled value and a brand-new player stays ×1. MultRebirth (≥1) carries the
-- base 1. Any future independent multiplier adds its own (mult-1) the same way.
--   moneyMult = MultRebirth + (inCommunity ? COMMUNITY.mult-1 : 0) + (moneyTierMult-1)
local function moneyMult(multRebirth, moneyTierMult, inCommunity)
	local communityBonus = if inCommunity then COMMUNITY.mult - 1 else 0
	local tierBonus = moneyTierMult - 1
	return multRebirth + communityBonus + tierBonus
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
