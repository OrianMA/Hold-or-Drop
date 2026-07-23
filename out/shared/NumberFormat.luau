-- Compiled with roblox-ts v3.0.0
-- ── Number formatting ─────────────────────────────────────────────────────────
-- Short-scale abbreviation used by most popular Roblox idle / simulator games
-- (Pet Simulator, Steal a Brainrot, etc.). Cheap to call — no log10, no
-- per-call allocation beyond the final string. Extend SUFFIXES to support
-- larger magnitudes; THRESHOLDS rebuilds automatically.
--
--  1_000             → "1K"
--  15_500            → "15.5K"
--  1_250_000         → "1.25M"
--  2_000_000_000     → "2B"
--  1_000_000_000_000 → "1T"
-- Each entry covers 10^(3 * index). "" at index 0 is the < 1000 range.
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg" }
-- Pre-computed thresholds — avoids math.log10 calls (which suffer float
-- precision issues around power-of-ten boundaries) and lets the formatter
-- scan from largest tier to smallest in O(n) on a small constant array.
local THRESHOLDS = {}
for i = 0, #SUFFIXES - 1 do
	local _arg0 = 10 ^ (i * 3)
	table.insert(THRESHOLDS, _arg0)
end
-- Truncates to 2 decimals and trims trailing zeros so "1.00M" renders as "1M",
-- "1.50M" as "1.5M", "1.25M" stays "1.25M".
-- Float epsilon absorbs IEEE 754 jitter so e.g. 1.25 × 100 doesn't collapse to
-- 124.999... and lose the last digit.
local function formatScaled(scaled)
	local hundredths = math.floor(scaled * 100 + 1e-7)
	if hundredths % 100 == 0 then
		return tostring(hundredths / 100)
	end
	if hundredths % 10 == 0 then
		return string.format("%.1f", hundredths / 100)
	end
	return string.format("%.2f", hundredths / 100)
end
-- Main entry point. Handles negatives, NaN, ±Infinity. Returns the integer form
-- (no decimals) for |value| < 1000 — matching how popular idle games render
-- "small" amounts.
local function FormatNumber(value)
	-- NaN — value !== value is the canonical check (NaN is the only number
	-- that isn't equal to itself).
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	if value == -math.huge then
		return "-∞"
	end
	local isNegative = value < 0
	local abs = math.abs(value)
	local sign = if isNegative then "-" else ""
	if abs < 1000 then
		return `{sign}{math.floor(abs)}`
	end
	-- Walk from highest tier to lowest — first match wins.
	for i = #SUFFIXES - 1, 1, -1 do
		if abs >= THRESHOLDS[i + 1] then
			return `{sign}{formatScaled(abs / THRESHOLDS[i + 1])}{SUFFIXES[i + 1]}`
		end
	end
	return `{sign}{math.floor(abs)}`
end
-- Like FormatNumber but rounds the abbreviated value to a whole number (no
-- decimals) — "15.5K" → "16K", "1.25M" → "1M". Used for shop prices where a
-- clean rounded figure reads better than a precise fractional one. Rolls up to
-- the next tier when rounding pushes the mantissa to 1000 (e.g. 999.6K → "1M").
local function FormatNumberRounded(value)
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	if value == -math.huge then
		return "-∞"
	end
	local isNegative = value < 0
	local abs = math.abs(value)
	local sign = if isNegative then "-" else ""
	if abs < 1000 then
		return `{sign}{math.floor(abs)}`
	end
	for i = #SUFFIXES - 1, 1, -1 do
		if abs >= THRESHOLDS[i + 1] then
			local mantissa = math.round(abs / THRESHOLDS[i + 1])
			local tier = i
			-- Rounding can bump the mantissa to 1000 — carry into the next suffix.
			if mantissa >= 1000 and tier < #SUFFIXES - 1 then
				tier += 1
				mantissa = math.round(abs / THRESHOLDS[tier + 1])
			end
			return `{sign}{mantissa}{SUFFIXES[tier + 1]}`
		end
	end
	return `{sign}{math.floor(abs)}`
end
-- Convenience for currency labels — same formatter, prefixed with the $ sign.
-- Negative amounts render as "-$5" (sign first), matching typical UX in shops.
local function FormatCash(value)
	if value ~= value then
		return "$0"
	end
	if value < 0 then
		return `-${FormatNumber(-value)}`
	end
	return `{FormatNumber(value)}`
end
-- Duration label for the playtime leaderboard. Coarse on purpose (top unit + the
-- next one): "2j 5h", "3h 12m", "45m", "30s". Negatives / NaN clamp to "0s".
local function formatDuration(totalSeconds)
	if totalSeconds ~= totalSeconds then
		return "0s"
	end
	local s = math.max(0, math.floor(totalSeconds))
	local days = math.floor(s / 86400)
	local hours = math.floor((s % 86400) / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local seconds = s % 60
	if days > 0 then
		return `{days}j {hours}h`
	end
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	if minutes > 0 then
		return `{minutes}m`
	end
	return `{seconds}s`
end
return {
	FormatNumber = FormatNumber,
	FormatNumberRounded = FormatNumberRounded,
	FormatCash = FormatCash,
	formatDuration = formatDuration,
	SUFFIXES = SUFFIXES,
}
