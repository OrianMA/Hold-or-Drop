#!/usr/bin/env node
// ── Simulateur d'économie — Ride a Rocket ────────────────────────────────────────
// Sert de suite de tests pour l'équilibrage. Il LIT les constantes directement dans
// les sources TypeScript (pas de copie), reconstruit le run et la boucle d'achat,
// puis vérifie les critères du design.
//
//   node tools/economy-sim.js            → tableau + critères, exit 1 si un critère échoue
//   node tools/economy-sim.js --verbose  → détail run par run des cycles R0 et R1
//
// Modèle : un joueur qui claim au temps maximisant l'espérance de gain et achète à
// chaque retour au shop l'upgrade au meilleur gain de revenu par dollar. Un vrai
// joueur fait moins bien → les durées réelles sont un peu plus longues.

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const VERBOSE = process.argv.includes("--verbose");

// Overhead d'un run hors temps de vol : explosion, animation de paiement, retour au bouton.
const RUN_OVERHEAD = 18;

// ── Lecture des constantes dans les sources ─────────────────────────────────────

function src(rel) {
	return fs.readFileSync(path.join(ROOT, rel), "utf8");
}

// `export const NAME = 12.5;`
function topConst(text, name) {
	const m = text.match(new RegExp(`export const ${name}\\s*=\\s*(-?[0-9.]+)`));
	if (!m) throw new Error(`constante export introuvable : ${name}`);
	return Number(m[1]);
}

// `const NAME = 0.8;` (module-level, non exporté)
function localConst(text, name) {
	const m = text.match(new RegExp(`\\bconst ${name}\\s*=\\s*(-?[0-9.]+)`));
	if (!m) throw new Error(`constante locale introuvable : ${name}`);
	return Number(m[1]);
}

// `export const BLOCK = { ... field: 12.5, ... };`
function field(text, block, name) {
	const b = text.match(new RegExp(`export const ${block}\\s*=\\s*\\{([\\s\\S]*?)\\n\\};`));
	if (!b) throw new Error(`bloc introuvable : ${block}`);
	const m = b[1].match(new RegExp(`\\b${name}\\s*:\\s*(-?[0-9.]+)`));
	if (!m) throw new Error(`champ introuvable : ${block}.${name}`);
	return Number(m[1]);
}

const S_ROCKET = src("src/shared/RocketGameConfig.ts");
const S_RES = src("src/shared/ResistanceCurve.ts");
const S_BAL = src("src/shared/ShopBalance.ts");
const S_CFG = src("src/shared/ShopConfig.ts");
const S_GAME = src("src/server/modules/ButtonInGameModule.ts");

const flat = (t) => t.replace(/\s+/g, " ");

// Formes de code attendues, détectées UNE FOIS (elles sont relues des milliers de fois
// par la boucle de simulation — ne pas les recalculer à chaque appel).
const RES_FRONT_LOADED = flat(S_RES).includes("(1 - n) ** RESISTANCE_SAFE_WINDOW_CURVE");
const MULT_MODEL_MULTIPLICATIVE = flat(S_CFG).includes("return multRebirth * (1 + communityBonus + tierBonus);");

const C = {
	ACCEL: topConst(S_ROCKET, "ROCKET_ACCEL"),
	MAXSPEED: topConst(S_ROCKET, "ROCKET_MAX_SPEED"),
	MULT_PER_STUD: topConst(S_ROCKET, "MULTIPLIER_PER_STUD"),
	MULT_TICK: topConst(S_ROCKET, "MULTIPLIER_TICK_RATE"),
	START_MULT: topConst(S_ROCKET, "STARTING_MULTIPLIER"),
	RISK_RAMP: topConst(S_ROCKET, "RISK_RAMP_DURATION"),

	RES_MAX_LEVEL: topConst(S_RES, "RESISTANCE_MAX_LEVEL"),
	RES_MAX_REDUCTION: topConst(S_RES, "RESISTANCE_MAX_REDUCTION"),
	RES_REDUCTION_CURVE: topConst(S_RES, "RESISTANCE_REDUCTION_CURVE"),
	RES_MAX_SAFE: topConst(S_RES, "RESISTANCE_MAX_SAFE_WINDOW"),
	RES_SAFE_CURVE: topConst(S_RES, "RESISTANCE_SAFE_WINDOW_CURVE"),

	MAX_RISK: localConst(S_GAME, "MAX_RISK"),
	TICK: localConst(S_GAME, "TICK_RATE"),
	LOSS_DIV: localConst(S_GAME, "LOSS_CONSOLATION_DIVISOR"),

	BC_BASE: field(S_BAL, "BASE_CASH", "baseValue"),
	BC_GROWTH: field(S_BAL, "BASE_CASH", "valueGrowth"),
	BC_PRICE: field(S_BAL, "BASE_CASH", "startPrice"),
	RS_BASE: field(S_BAL, "ROCKET_SPEED", "baseValue"),
	RS_PRICE: field(S_BAL, "ROCKET_SPEED", "startPrice"),
	RES_PRICE: field(S_BAL, "RESISTANCE", "startPrice"),
	RB_BASE_COST: field(S_BAL, "REBIRTH", "baseCost"),
	RB_COST_GROWTH: field(S_BAL, "REBIRTH", "costGrowth"),
};

// priceGrowth par stat (Task 5). Avant Task 5 ces champs n'existent pas → on retombe
// sur PRICE_GROWTH global, ce qui laisse le simulateur exécutable pendant la migration.
function priceGrowthOf(block) {
	try {
		return field(S_BAL, block, "priceGrowth");
	} catch {
		return topConst(S_BAL, "PRICE_GROWTH");
	}
}
C.BC_PRICE_GROWTH = priceGrowthOf("BASE_CASH");
C.RS_PRICE_GROWTH = priceGrowthOf("ROCKET_SPEED");
C.RES_PRICE_GROWTH = priceGrowthOf("RESISTANCE");

// multGrowth (Task 6). Avant Task 6, la table multTable/multTail est encore en place.
let REBIRTH_MULT;
try {
	const g = field(S_BAL, "REBIRTH", "multGrowth");
	REBIRTH_MULT = (R) => g ** R;
} catch {
	const table = S_BAL.match(/multTable:\s*\[([^\]]*)\]/)[1].split(",").map((s) => Number(s.trim()));
	const tail = field(S_BAL, "REBIRTH", "multTail");
	REBIRTH_MULT = (R) => (R <= table.length - 1 ? table[R] : table[table.length - 1] + (R - table.length + 1) * tail);
}

// ── Modèle ───────────────────────────────────────────────────────────────────────

const price = (start, growth, lvl) => Math.floor(start * growth ** lvl);
const baseCashVal = (lvl) => Math.floor(C.BC_BASE * C.BC_GROWTH ** lvl);
const speedVal = (lvl) => C.RS_BASE + lvl;
const rebirthCost = (R) => Math.floor(C.RB_BASE_COST * C.RB_COST_GROWTH ** R);

// Doit refléter shared/ResistanceCurve.ts. La forme de safeWindow est vérifiée par le
// critère 2b ci-dessous (assertion sur la source), donc on code ici la forme cible.
function resParams(lvl) {
	const n = Math.min(Math.max(lvl / C.RES_MAX_LEVEL, 0), 1);
	const reduction = C.RES_MAX_REDUCTION * (1 - (1 - n) ** C.RES_REDUCTION_CURVE);
	const safeWindow = RES_FRONT_LOADED
		? C.RES_MAX_SAFE * (1 - (1 - n) ** C.RES_SAFE_CURVE)
		: n ** C.RES_SAFE_CURVE * C.RES_MAX_SAFE;
	return { riskScale: 1 - reduction, safeWindow };
}

// Miroir de ShopConfig.moneyMult, dans la forme réellement présente dans la source.
function moneyMultJs(multRebirth, moneyTierMult, inCommunity) {
	const communityBonus = inCommunity ? 1 : 0; // COMMUNITY.mult = 2 → bonus +1
	const tierBonus = moneyTierMult - 1;
	return MULT_MODEL_MULTIPLICATIVE
		? multRebirth * (1 + communityBonus + tierBonus)
		: multRebirth + communityBonus + tierBonus;
}

function multAt(speedValue, seconds) {
	let m = C.START_MULT;
	const accel = C.ACCEL * speedValue;
	const maxSpeed = C.MAXSPEED * speedValue;
	for (let t = C.MULT_TICK; t <= seconds + 1e-6; t += C.MULT_TICK) {
		m += Math.min(accel * t, maxSpeed) * C.MULT_TICK * C.MULT_PER_STUD;
	}
	return m;
}

function survival(p, T) {
	let s = 1;
	for (let t = C.TICK; t <= T + 1e-9; t += C.TICK) {
		if (t > p.safeWindow) {
			const x = Math.min((t - p.safeWindow) / C.RISK_RAMP, 1);
			s *= 1 - C.MAX_RISK * x * x * p.riskScale;
		}
	}
	return s;
}

// Temps de claim maximisant l'espérance de gain.
function bestClaim(base, speedValue, resLevel) {
	const p = resParams(resLevel);
	let best = { T: 1, ev: 0, pS: 1, mult: 1 };
	for (let T = 1; T <= 120; T++) {
		const pS = survival(p, T);
		const m = multAt(speedValue, T);
		const ev = pS * base * m + (1 - pS) * (base / C.LOSS_DIV);
		if (ev > best.ev) best = { T, ev, pS, mult: m };
	}
	return best;
}

function medianSurvival(resLevel) {
	const p = resParams(resLevel);
	for (let t = C.TICK; t < 300; t += C.TICK) if (survival(p, t) < 0.5) return t;
	return 300;
}

// ── Boucle de jeu ────────────────────────────────────────────────────────────────

function simulate(maxRebirths) {
	let money = 0, Lb = 0, Ls = 0, Lr = 0, R = 0, peakPrev = 0;
	let cyc = { runs: 0, time: 0, recover: null, peak: 0 };
	const rows = [];
	const ev = (lb, ls, lr, r) => bestClaim(Math.floor(baseCashVal(lb) * REBIRTH_MULT(r)), speedVal(ls), lr);

	for (let guard = 0; guard < 20000 && R < maxRebirths; guard++) {
		const b = ev(Lb, Ls, Lr, R);
		money += b.ev;
		cyc.runs++;
		cyc.time += RUN_OVERHEAD + b.T;
		cyc.peak = Math.max(cyc.peak, b.ev);
		if (cyc.recover === null && b.ev >= peakPrev) cyc.recover = cyc.runs;

		if (VERBOSE && R < 2)
			console.log(
				`   R${R} run#${String(cyc.runs).padStart(2)} | ${Math.round(b.ev).toLocaleString("fr-FR").padStart(13)}$ | vol ${String(b.T).padStart(2)}s survie ${String(Math.round(b.pS * 100)).padStart(3)}% mult x${b.mult.toFixed(1).padStart(6)} | BC${String(Lb).padStart(2)} RS${String(Ls).padStart(2)} RE${String(Lr).padStart(2)}`,
			);

		let bought = true;
		while (bought) {
			bought = false;
			const cur = ev(Lb, Ls, Lr, R).ev;
			const opts = [
				{ p: price(C.BC_PRICE, C.BC_PRICE_GROWTH, Lb), e: ev(Lb + 1, Ls, Lr, R).ev, f: () => Lb++ },
				{ p: price(C.RS_PRICE, C.RS_PRICE_GROWTH, Ls), e: ev(Lb, Ls + 1, Lr, R).ev, f: () => Ls++ },
				{ p: price(C.RES_PRICE, C.RES_PRICE_GROWTH, Lr), e: ev(Lb, Ls, Lr + 1, R).ev, f: () => Lr++, cap: Lr >= C.RES_MAX_LEVEL },
			];
			let bo = null, br = 0;
			for (const o of opts) {
				if (o.cap || o.p > money) continue;
				const g = (o.e - cur) / o.p;
				if (g > br) { br = g; bo = o; }
			}
			if (bo && money >= rebirthCost(R)) bo = null; // on épargne pour le rebirth
			if (bo) { money -= bo.p; bo.f(); bought = true; }
		}

		if (money >= rebirthCost(R)) {
			rows.push({ R, runs: cyc.runs, min: +(cyc.time / 60).toFixed(1), recover: cyc.recover, Lb, Ls, Lr, T: b.T, peak: cyc.peak });
			peakPrev = cyc.peak;
			money = 0; Lb = Ls = Lr = 0; R++;
			cyc = { runs: 0, time: 0, recover: null, peak: 0 };
		}
	}
	return rows;
}

// ── Critères ─────────────────────────────────────────────────────────────────────

const failures = [];
function check(label, ok, detail) {
	console.log(`${ok ? "  OK  " : " ÉCHEC"} | ${label} — ${detail}`);
	if (!ok) failures.push(label);
}

if (VERBOSE) console.log("--- cycles R0 et R1, run par run ---");
const rows = simulate(8);

console.log("\nR | runs | min  | récup. | BC  RS  RE | vol  | revenu pic du cycle");
for (const r of rows)
	console.log(
		`${r.R} | ${String(r.runs).padStart(4)} | ${String(r.min).padStart(4)} | ${String(r.recover ?? "-").padStart(6)} | ${String(r.Lb).padStart(2)}  ${String(r.Ls).padStart(2)}  ${String(r.Lr).padStart(2)} | ${String(r.T).padStart(3)}s | ${Math.round(r.peak).toLocaleString("fr-FR")}`,
	);

console.log("\nniv Resistance | fenêtre garantie | survie médiane");
for (const L of [0, 1, 2, 3, 5, 10, 20, 30])
	console.log(`${String(L).padStart(14)} | ${resParams(L).safeWindow.toFixed(1).padStart(15)}s | ${medianSurvival(L).toFixed(1)}s`);

console.log("");

// 1 — le premier run rapporte assez pour un achat immédiat
const first = bestClaim(baseCashVal(0) * REBIRTH_MULT(0), speedVal(0), 0);
const cheapest = Math.min(C.BC_PRICE, C.RS_PRICE, C.RES_PRICE);
check("1. premier run ≥ 100$", first.ev >= 100, `${Math.round(first.ev)}$ (claim optimal ${first.T}s)`);
check("1b. achat possible dès le run 1", first.ev >= cheapest, `revenu ${Math.round(first.ev)}$ vs upgrade la moins chère ${cheapest}$`);

// 2 — Resistance L1 achète une vraie durée
const r1 = resParams(1);
check("2. Resistance L1 : fenêtre ≥ 1.0s", r1.safeWindow >= 1.0, `${r1.safeWindow.toFixed(2)}s`);
check("2b. Resistance L1 : survie médiane ≥ 8.0s", medianSurvival(1) >= 8.0, `${medianSurvival(1).toFixed(1)}s (L0 = ${medianSurvival(0).toFixed(1)}s)`);
check("2c. safeWindow front-loaded", RES_FRONT_LOADED, "forme MAX * (1 - (1-n)^C) attendue dans ResistanceCurve.ts");

// 3 — le premier niveau de vitesse se voit
const m10 = multAt(speedVal(1), 10);
check("3. RocketSpeed L1 : mult à 10s ≥ x4.0", m10 >= 4.0, `x${m10.toFixed(2)} (L0 = x${multAt(speedVal(0), 10).toFixed(2)})`);

// 4 — durée des cycles
const cycles = rows.filter((r) => r.R >= 1 && r.R <= 7);
const bad = cycles.filter((r) => r.min < 4.5 || r.min > 18);
check("4. cycles R1..R7 entre 4.5 et 18 min", bad.length === 0, bad.length ? `hors bornes : ${bad.map((r) => `R${r.R}=${r.min}min`).join(", ")}` : cycles.map((r) => `${r.min}`).join(" / ") + " min");

// 5 — retour au niveau précédent
const slow = cycles.filter((r) => r.recover === null || r.recover > 3);
check("5. récupération du pic ≤ 3 runs (R1..R7)", slow.length === 0, slow.length ? `trop lent : ${slow.map((r) => `R${r.R}=${r.recover ?? "jamais"}`).join(", ")}` : cycles.map((r) => r.recover).join(" / ") + " runs");

// 6 — un pass money x2 double bien le revenu, quel que soit le niveau de rebirth
check("6. moneyMult multiplicatif", MULT_MODEL_MULTIPLICATIVE, "ShopConfig.moneyMult doit être multRebirth * (1 + communityBonus + tierBonus)");
const without = moneyMultJs(REBIRTH_MULT(3), 1, false);
const withPass = moneyMultJs(REBIRTH_MULT(3), 2, false);
check(
	"6b. un pass x2 double le revenu à R3",
	Math.abs(withPass / without - 2) < 1e-9,
	`x${without} → x${withPass} (ratio ${(withPass / without).toFixed(3)}, attendu 2.000)`,
);

console.log(failures.length === 0 ? "\nTous les critères sont verts.\n" : `\n${failures.length} critère(s) en échec.\n`);
process.exit(failures.length === 0 ? 0 : 1);
