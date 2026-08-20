-- Compiled with roblox-ts v3.0.0
-- ── Daily reward ──────────────────────────────────────────────────────────────
-- Reward = EffectiveBaseCash × dailyMultiplier(streak), where `streak` is the number
-- of CONSECUTIVE days the player has claimed (1 the first day, 2 the next, …). The
-- Robux "3X Claim" developer product triples that total.
--
-- Single source of truth shared by both sides:
--   • server (DailyRewardService) owns the streak, the day boundary and the grant.
--   • client (DailyRewardsBehavior) reads the published attributes and prompts the product.
local SECONDS_PER_DAY = 86400
-- Robux "3X Claim" developer product — DailyRewards/ButtonsFrame/X3ClaimButtonFrame.
-- Price is configured on the Roblox dashboard, not here.
local DAILY_X3_PRODUCT_ID = 3709014909
local DAILY_X3_MULTIPLIER = 3
-- True if the purchased productId is the daily "3X Claim" product. Server-side lookup,
-- mirrors amountForProduct / levelGrantForProduct / isSafeRebirthProduct.
local function isDailyX3Product(productId)
	return productId == DAILY_X3_PRODUCT_ID
end
-- Day N pays ×N — deliberately uncapped. This is the ONLY place the streak turns into
-- a multiplier: clamp here (e.g. `math.min(streak, 7)`) if the top end ever needs
-- flattening, nothing else reads the raw streak.
local function dailyMultiplier(streak)
	return math.max(1, math.floor(streak))
end
-- UTC day index. The reward resets at UTC midnight for everyone — a fixed global
-- boundary, so a player can't farm the streak by changing timezone.
local function dayIndex(atTime)
	return math.floor(atTime / SECONDS_PER_DAY)
end
-- Attributes published by DailyRewardService (replicated — the client reads them
-- directly instead of asking the server).
--   DailyMultiplier — the multiplier a claim would apply RIGHT NOW
--   DailyClaimed    — true once today's reward has been taken
--   DailyAutoOpen   — compteur de demandes d'ouverture (voir plus bas)
local DAILY_MULTIPLIER_ATTR = "DailyMultiplier"
local DAILY_CLAIMED_ATTR = "DailyClaimed"
-- Auto-open is an ATTRIBUTE, not a RemoteEvent, on purpose: the server decides while
-- the player is still loading, and a fired event would be lost if the client hasn't
-- connected its handler yet. An attribute is simply read whenever the client is ready
-- — and its change signal couvre le cas où le serveur le lève plus tard (premier
-- rebirth d'un joueur qui était en tutorial).
--
-- C'est un COMPTEUR, pas un booléen : le client ouvre le popup dès que la valeur
-- dépasse celle qu'il a déjà traitée. Un booléen ne peut pas exprimer "rouvre" (le
-- passer de true à true ne notifie personne, et le remettre à false d'abord dépend de
-- la façon dont la réplication regroupe les écritures d'une même frame). Le compteur
-- donne aussi le "une seule fois" gratuitement : le serveur ne demande qu'une fois.
local DAILY_AUTO_OPEN_ATTR = "DailyAutoOpen"
return {
	isDailyX3Product = isDailyX3Product,
	dailyMultiplier = dailyMultiplier,
	dayIndex = dayIndex,
	DAILY_X3_PRODUCT_ID = DAILY_X3_PRODUCT_ID,
	DAILY_X3_MULTIPLIER = DAILY_X3_MULTIPLIER,
	DAILY_MULTIPLIER_ATTR = DAILY_MULTIPLIER_ATTR,
	DAILY_CLAIMED_ATTR = DAILY_CLAIMED_ATTR,
	DAILY_AUTO_OPEN_ATTR = DAILY_AUTO_OPEN_ATTR,
}
