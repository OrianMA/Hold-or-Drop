// ── Number formatting ─────────────────────────────────────────────────────────
// Short-scale abbreviation used by most popular Roblox idle / simulator games
// (Pet Simulator, Steal a Brainrot, etc.). Cheap to call — no log10, no
// per-call allocation beyond the final string. Extend SUFFIXES to support
// larger magnitudes; THRESHOLDS rebuilds automatically.
//
//  1_000             → "1K"
//  15_500            → "15.5K"
//  1_250_000         → "1.25M"
//  2_000_000_000     → "2B"
//  1_000_000_000_000 → "1T"

// Each entry covers 10^(3 * index). "" at index 0 is the < 1000 range.
export const SUFFIXES = [
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
] as const;

// Pre-computed thresholds — avoids math.log10 calls (which suffer float
// precision issues around power-of-ten boundaries) and lets the formatter
// scan from largest tier to smallest in O(n) on a small constant array.
const THRESHOLDS: number[] = [];
for (let i = 0; i < SUFFIXES.size(); i++) {
	THRESHOLDS.push(10 ** (i * 3));
}

// Truncates to 2 decimals and trims trailing zeros so "1.00M" renders as "1M",
// "1.50M" as "1.5M", "1.25M" stays "1.25M".
// Float epsilon absorbs IEEE 754 jitter so e.g. 1.25 × 100 doesn't collapse to
// 124.999... and lose the last digit.
function formatScaled(scaled: number): string {
	const hundredths = math.floor(scaled * 100 + 1e-7);
	if (hundredths % 100 === 0) return tostring(hundredths / 100);
	if (hundredths % 10 === 0) return string.format("%.1f", hundredths / 100);
	return string.format("%.2f", hundredths / 100);
}

// Main entry point. Handles negatives, NaN, ±Infinity. Returns the integer form
// (no decimals) for |value| < 1000 — matching how popular idle games render
// "small" amounts.
export function FormatNumber(value: number): string {
	// NaN — value !== value is the canonical check (NaN is the only number
	// that isn't equal to itself).
	if (value !== value) return "0";
	if (value === math.huge) return "∞";
	if (value === -math.huge) return "-∞";

	const isNegative = value < 0;
	const abs = math.abs(value);
	const sign = isNegative ? "-" : "";

	if (abs < 1000) return `${sign}${math.floor(abs)}`;

	// Walk from highest tier to lowest — first match wins.
	for (let i = SUFFIXES.size() - 1; i >= 1; i--) {
		if (abs >= THRESHOLDS[i]) {
			return `${sign}${formatScaled(abs / THRESHOLDS[i])}${SUFFIXES[i]}`;
		}
	}

	return `${sign}${math.floor(abs)}`;
}

// Convenience for currency labels — same formatter, prefixed with the $ sign.
// Negative amounts render as "-$5" (sign first), matching typical UX in shops.
export function FormatCash(value: number): string {
	if (value !== value) return "$0";
	if (value < 0) return `-$${FormatNumber(-value)}`;
	return `${FormatNumber(value)}`;
}
