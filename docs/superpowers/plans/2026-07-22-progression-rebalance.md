# Rééquilibrage progression & rebirth — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre les premières améliorations visibles, la Resistance lisible en secondes, et le rebirth immédiatement rentable (retour au niveau précédent en ~3 runs), en ne touchant que des chiffres, l'affichage du shop et un pulse sur le bouton Claim.

**Architecture:** Les constantes de gameplay descendent dans `shared/` pour que client et serveur affichent la même chose. Un simulateur Node (`tools/economy-sim.js`) lit les constantes **directement dans les sources TypeScript** et sert de suite de tests : il échoue sur la config actuelle (Task 2) et devient vert au fil des Tasks 3-6. Les tâches UI (7-9) se vérifient par `npm run build` puis en jeu dans Studio.

**Tech Stack:** roblox-ts (TypeScript → Luau), Rojo, Node 24 pour le simulateur. Aucun framework de test dans le projet — le simulateur EST le harness.

## Global Constraints

- Référence de design : `docs/superpowers/specs/2026-07-22-progression-rebalance-design.md`. Tous les chiffres viennent de là.
- **Ne jamais éditer `out/` à la main.** `out/` est généré par `npm run build`. Le build réécrit des fichiers en CRLF sans changement réel — au moment de `git add`, **ne stager que les `out/` correspondant aux fichiers `src/` réellement modifiés dans la tâche**, jamais `git add out/` en bloc.
- Toujours lancer `npm run build` avant de committer une tâche qui touche `src/`. Zéro erreur de compilation.
- `ARCHITECTURE.md` doit rester synchrone (Task 10).
- **Aucune migration DataStore.** Les niveaux (`BaseCashLevel`, `RocketSpeedLevel`, `ResistanceLevel`) et `Rebirths` sont la source de vérité persistée ; toutes les valeurs sont dérivées. Ne pas bumper `STORE_NAME`.
- Hors périmètre, ne pas toucher : `RebirthService.safeRebirth`, `RESISTANCE_PASS.addLevels`, `MoneyProductService`, `LevelProducts`.
- Le projet est en français dans les commentaires récents et en anglais dans les plus anciens — suivre le fichier édité.

## Structure des fichiers

| Fichier | Responsabilité | Task |
|---|---|---|
| `src/shared/ResistanceCurve.ts` | **nouveau** — constantes Resistance + `resistanceRiskParams`. Module feuille, aucun import. | 1, 4 |
| `src/server/modules/ButtonInGameModule.ts` | Boucle de risque. Perd les constantes/la fonction, les importe. | 1 |
| `tools/economy-sim.js` | **nouveau** — modèle d'économie + extraction des constantes depuis les sources + assertions. | 2 |
| `src/shared/RocketGameConfig.ts` | Constantes de vol + `multiplierAfter()` (aperçu shop). | 3, 7 |
| `src/shared/ShopBalance.ts` | Tous les nombres de l'économie. | 5, 6 |
| `src/shared/ShopConfig.ts` | Formules : prix par stat, `moneyMult`, `rebirthMult`, `display`. | 5, 6, 7 |
| `src/client/behaviors/ShopItemsController.ts` | Rendu des 3 boutons du shop. | 7 |
| `src/client/behaviors/BoostShopController.ts` | Readout du multiplicateur. | 8 |
| `src/client/behaviors/RocketLaunchBehavior.ts` | Pulse du `ClaimButton`. | 9 |
| `ARCHITECTURE.md` | §6.3, §6.6, §6.8, §6.9. | 10 |

---

### Task 1 : Descendre la courbe de Resistance dans `shared/`

Refactor pur — **aucun changement de comportement**. Les valeurs et la formule restent
exactement celles d'aujourd'hui. Le but est que le client puisse importer la courbe
(Task 7) et que le simulateur ait un fichier stable à lire (Task 2).

**Files:**
- Create: `src/shared/ResistanceCurve.ts`
- Modify: `src/server/modules/ButtonInGameModule.ts:69-99` (bloc « Resistance → risk model »)

**Interfaces:**
- Consumes: rien.
- Produces: `RESISTANCE_MAX_LEVEL: number`, `RESISTANCE_MAX_REDUCTION: number`, `RESISTANCE_REDUCTION_CURVE: number`, `RESISTANCE_MAX_SAFE_WINDOW: number`, `RESISTANCE_SAFE_WINDOW_CURVE: number`, `interface RiskParams { readonly riskScale: number; readonly safeWindow: number }`, `resistanceRiskParams(resistance: number): RiskParams`.

- [ ] **Step 1 : Créer `src/shared/ResistanceCurve.ts`**

```ts
// ── Resistance → risk model ──────────────────────────────────────────────────────
// Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
// s'accordent sur ce que vaut un niveau de Resistance.
//
// Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
// d'explosion de deux façons indépendantes :
//   • safeWindow — secondes de début de vol où le risque est forcé à 0. C'est la
//     valeur montrée au joueur ("X s garanties").
//   • riskScale  — met à l'échelle toute la courbe de risque APRÈS la fenêtre. Levier
//     secondaire : la survie médiane ne croît qu'en riskScale^(-1/3), donc il ne peut
//     pas être rendu lisible seul.
// À resistance 0 les deux termes sont neutres → courbe identique à celle d'origine.

export const RESISTANCE_MAX_LEVEL = 100;
export const RESISTANCE_MAX_REDUCTION = 0.99; // risque plancher ×0.01 au niveau 100
export const RESISTANCE_REDUCTION_CURVE = 12; // ↑ = plus front-loaded
export const RESISTANCE_MAX_SAFE_WINDOW = 15; // secondes garanties au niveau 100
export const RESISTANCE_SAFE_WINDOW_CURVE = 2.5;

export interface RiskParams {
	readonly riskScale: number;
	readonly safeWindow: number;
}

export function resistanceRiskParams(resistance: number): RiskParams {
	const n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1);
	const reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ** RESISTANCE_REDUCTION_CURVE);
	const safeWindow = n ** RESISTANCE_SAFE_WINDOW_CURVE * RESISTANCE_MAX_SAFE_WINDOW;
	return { riskScale: 1 - reduction, safeWindow };
}
```

- [ ] **Step 2 : Supprimer le bloc dupliqué dans `ButtonInGameModule.ts`**

Supprimer intégralement les lignes 69 à 99 (du commentaire `// ── Resistance → risk model`
jusqu'à la fermeture de `resistanceRiskParams`), c'est-à-dire les 5 constantes
`RESISTANCE_*`, l'`interface RiskParams` et la fonction `resistanceRiskParams`.

**Ne pas toucher** `riskAt` (ligne 103) ni `rollExplosionTime` — ils restent dans ce
fichier, c'est la boucle de risque du serveur.

- [ ] **Step 3 : Ajouter l'import dans `ButtonInGameModule.ts`**

Juste après l'import existant de `shared/RocketGameConfig` (lignes 10-16) :

```ts
import { RiskParams, resistanceRiskParams } from "shared/ResistanceCurve";
```

- [ ] **Step 4 : Compiler**

```bash
npm run build
```

Attendu : compilation sans erreur. Si `resistanceRiskParams` est signalée comme non
utilisée dans `ButtonInGameModule`, c'est que l'appel d'origine a été supprimé par erreur —
il doit rester (recherche : `resistanceRiskParams(`).

- [ ] **Step 5 : Vérifier qu'aucune valeur n'a bougé**

```bash
git diff -U0 src/server/modules/ButtonInGameModule.ts
```

Attendu : uniquement des suppressions + 1 ligne d'import ajoutée. **Aucun nombre modifié.**

- [ ] **Step 6 : Commit**

```bash
git add src/shared/ResistanceCurve.ts src/server/modules/ButtonInGameModule.ts out/shared/ResistanceCurve.luau out/server/modules/ButtonInGameModule.luau
git commit -m "refactor: descendre la courbe de Resistance dans shared/ResistanceCurve"
```

---

### Task 2 : Le harness — `tools/economy-sim.js`

Le simulateur lit les constantes **dans les sources TypeScript** (pas de copie qui dérive)
et vérifie 6 critères mesurables. Sur la config actuelle il doit **échouer** : c'est le
test rouge qui pilote les Tasks 3-6.

**Files:**
- Create: `tools/economy-sim.js`

**Interfaces:**
- Consumes: les constantes de `src/shared/RocketGameConfig.ts`, `src/shared/ResistanceCurve.ts` (Task 1), `src/shared/ShopBalance.ts`, `src/shared/ShopConfig.ts`, `src/server/modules/ButtonInGameModule.ts`.
- Produces: la commande `node tools/economy-sim.js` (exit 0 = tous les critères verts, exit 1 sinon).

- [ ] **Step 1 : Créer `tools/economy-sim.js`**

```js
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
const bad = cycles.filter((r) => r.min < 3.5 || r.min > 8);
check("4. cycles R1..R7 entre 3.5 et 8 min", bad.length === 0, bad.length ? `hors bornes : ${bad.map((r) => `R${r.R}=${r.min}min`).join(", ")}` : cycles.map((r) => `${r.min}`).join(" / ") + " min");

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
```

- [ ] **Step 2 : Lancer le simulateur — il doit ÉCHOUER**

```bash
node tools/economy-sim.js
```

Attendu : le tableau s'affiche, puis **au moins les critères 2, 2b, 2c, 3, 5, 6 et 6b en
ÉCHEC**, et le process sort en code 1. Repères sur la config actuelle : Resistance L1
fenêtre 0.00 s et survie médiane 7.5 s (identique à L0), mult à 10 s au niveau 1 = ×2.10,
récupération 5+ runs.

Si le script plante sur `constante introuvable`, c'est que Task 1 n'a pas été faite ou
qu'un nom a changé — corriger avant de continuer.

- [ ] **Step 3 : Vérifier le mode verbose**

```bash
node tools/economy-sim.js --verbose
```

Attendu : les runs des cycles R0 et R1 s'affichent avant le tableau.

- [ ] **Step 4 : Commit (baseline rouge)**

```bash
git add tools/economy-sim.js
git commit -m "test: simulateur d'économie lisant les constantes des sources (baseline rouge)"
```

---

### Task 3 : La fusée décolle vraiment

**Files:**
- Modify: `src/shared/RocketGameConfig.ts:28-29`

**Interfaces:**
- Consumes: rien.
- Produces: `ROCKET_ACCEL = 3`, `ROCKET_MAX_SPEED = 30` (inchangés en nom et en type).

- [ ] **Step 1 : Modifier les deux constantes**

Remplacer le bloc lignes 22-29 par :

```ts
// ── Rocket launch (RocketLauncher) ──────────────────────────────────────────────
// La fusée monte pendant le vol : la vitesse part de 0, monte de ROCKET_ACCEL
// (studs/s²) jusqu'à ROCKET_MAX_SPEED (studs/s), puis reste constante.
// Ces valeurs sont PAR UNITÉ DE ROCKET SPEED : launch() les multiplie par la stat du
// joueur. Au niveau 0 (valeur 1) la fusée atteint 30 studs/s en 10 s — assez pour que
// le multiplicateur bouge visiblement dès le premier run. Chaque niveau ajoute une
// unité entière, donc le premier achat double littéralement la vitesse ET la vitesse
// de montée du multiplicateur.
export const ROCKET_ACCEL = 3;
export const ROCKET_MAX_SPEED = 30;
```

- [ ] **Step 2 : Lancer le simulateur — le critère 3 passe au vert**

```bash
node tools/economy-sim.js
```

Attendu : `OK | 3. RocketSpeed L1 : mult à 10s ≥ x4.0 — x4.30 (L0 = x2.65)`.
Les critères 2, 2b, 2c, 5, 6, 6b restent en échec.

- [ ] **Step 3 : Compiler**

```bash
npm run build
```

Attendu : aucune erreur.

- [ ] **Step 4 : Commit**

```bash
git add src/shared/RocketGameConfig.ts out/shared/RocketGameConfig.luau
git commit -m "balance: tripler l'accélération et la vitesse max de la fusée par unité de Rocket Speed"
```

---

### Task 4 : Resistance — fenêtre garantie front-loaded

**Files:**
- Modify: `src/shared/ResistanceCurve.ts` (les 4 constantes de courbe + la formule de `safeWindow`)

**Interfaces:**
- Consumes: le module créé en Task 1.
- Produces: même API (`resistanceRiskParams`, `RiskParams`), valeurs et forme de courbe changées.

- [ ] **Step 1 : Remplacer les constantes et la formule**

Remplacer le bloc de commentaire + constantes + fonction par :

```ts
// ── Resistance → risk model ──────────────────────────────────────────────────────
// Partagé pour que le serveur (boucle de risque) et le client (affichage du shop)
// s'accordent sur ce que vaut un niveau de Resistance.
//
// Resistance est une stat de shop 0..100 (voir ShopConfig). Elle remodèle le risque
// d'explosion de deux façons indépendantes :
//   • safeWindow — secondes de début de vol où le risque est forcé à 0. FRONT-loaded :
//     les premiers niveaux achètent l'essentiel de la fenêtre, les derniers presque
//     rien. C'est la valeur montrée au joueur dans le shop ("X s garanties").
//   • riskScale  — met à l'échelle toute la courbe de risque APRÈS la fenêtre. Levier
//     SECONDAIRE : la survie médiane ne croît qu'en riskScale^(-1/3) (il faut diviser
//     le risque par 8 pour doubler la durée), donc il ne peut pas être rendu lisible
//     seul. C'est la raison du basculement de poids vers safeWindow.
// À resistance 0 les deux termes sont neutres → courbe identique à celle d'origine.
//
// Repères : L1 → 1.1 s garanties / survie médiane 8.5 s (contre 7.0 s à L0).
//           L5 → 4.1 s / 12.5 s.  L10 → 6.2 s / 15.5 s.  L30 → 7.9 s / 19.0 s (saturé).

export const RESISTANCE_MAX_LEVEL = 100;
export const RESISTANCE_MAX_REDUCTION = 0.75; // risque plancher ×0.25 au niveau 100
export const RESISTANCE_REDUCTION_CURVE = 13; // ↑ = plus front-loaded
export const RESISTANCE_MAX_SAFE_WINDOW = 8; // secondes garanties au niveau 100
export const RESISTANCE_SAFE_WINDOW_CURVE = 14; // ↑ = plus front-loaded

export interface RiskParams {
	readonly riskScale: number;
	readonly safeWindow: number;
}

export function resistanceRiskParams(resistance: number): RiskParams {
	const n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1);
	const reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ** RESISTANCE_REDUCTION_CURVE);
	const safeWindow = RESISTANCE_MAX_SAFE_WINDOW * (1 - (1 - n) ** RESISTANCE_SAFE_WINDOW_CURVE);
	return { riskScale: 1 - reduction, safeWindow };
}
```

- [ ] **Step 2 : Lancer le simulateur — les critères 2, 2b, 2c passent au vert**

```bash
node tools/economy-sim.js
```

Attendu :
```
  OK   | 2. Resistance L1 : fenêtre ≥ 1.0s — 1.00s
  OK   | 2b. Resistance L1 : survie médiane ≥ 8.0s — 8.5s (L0 = 7.0s)
  OK   | 2c. safeWindow front-loaded — ...
```
Le tableau des niveaux de Resistance doit afficher 1.0 s / 1.8 s / 2.6 s / 3.9 s / 6.0 s
pour les niveaux 1 / 2 / 3 / 5 / 10. Les critères 5, 6, 6b restent en échec.

- [ ] **Step 3 : Compiler**

```bash
npm run build
```

- [ ] **Step 4 : Commit**

```bash
git add src/shared/ResistanceCurve.ts out/shared/ResistanceCurve.luau
git commit -m "balance: fenêtre de sécurité front-loaded, Resistance lisible dès le niveau 1"
```

---

### Task 5 : Un prix par stat

**Files:**
- Modify: `src/shared/ShopBalance.ts` (blocs `BASE_CASH`, `ROCKET_SPEED`, `RESISTANCE`, suppression de `PRICE_GROWTH`)
- Modify: `src/shared/ShopConfig.ts` (`StatConfig`, `STATS`, `priceForLevel`, import)

**Interfaces:**
- Consumes: rien.
- Produces: `StatConfig` gagne `readonly priceGrowth: number`. `priceForLevel(stat, level)` garde sa signature. `PRICE_GROWTH` **n'est plus exporté**.

- [ ] **Step 1 : `ShopBalance.ts` — remplacer les blocs de prix**

Remplacer les lignes 12-50 (de `// Price multiplier applied per level…` jusqu'à la
fermeture du bloc `RESISTANCE`) par :

```ts
// Chaque stat a sa propre croissance de prix (`priceGrowth`). C'est nécessaire parce
// que les trois stats se MULTIPLIENT entre elles (revenu = BaseCash × mult(vitesse,
// temps de vol), et la Resistance rallonge le temps de vol) : avec une croissance
// unique l'économie s'emballe. Mur raide sur les stats d'argent, mur doux sur la
// Resistance pour qu'elle offre beaucoup de petits paliers.

// BaseCash — le gain de base du bouton. Sans plafond.
//   value = baseValue * valueGrowth ^ level   (L0=100, L10≈619, L20≈3.8K)
//   price = startPrice * priceGrowth ^ level  (L0→1 = 50)
//   Invariant : valueGrowth < priceGrowth (1.20 < 1.8) → le prix dépasse la valeur.
export const BASE_CASH = {
	baseValue: 100,
	valueGrowth: 1.2,
	startPrice: 50,
	priceGrowth: 1.8,
};

// Rocket Speed — pilote À LA FOIS la vitesse d'ascension et la vitesse de montée du
// multiplicateur (le multiplicateur suit la vitesse instantanée de la fusée). Entier,
// +1 par niveau, sans plafond.
//   value = baseValue + level   (L0=1 → mult ×2.6 à 10 s ; L1=2 → ×4.3 : le premier
//                                achat double littéralement le gain)
//   accel/vitesse max réels = value × les constantes de RocketGameConfig.
//   price = startPrice * priceGrowth ^ level  (L0→1 = 75)
export const ROCKET_SPEED = {
	baseValue: 1,
	startPrice: 75,
	priceGrowth: 1.7,
};

// Resistance — 0..100. Achetée +1 par niveau. Le nombre n'est PAS un pourcentage : il
// alimente la courbe de shared/ResistanceCurve.ts, qui le convertit en SECONDES DE VOL
// GARANTIES (c'est ce qu'affiche le shop). La courbe est front-loaded : L1 achète déjà
// 1.0 s garantie et +1.5 s de survie médiane, L30 n'achète plus rien.
//   value = level (0..100)
//   price = startPrice * priceGrowth ^ level   (L0→1 = 150)
//   Croissance douce (1.35) et prix de départ bas : la Resistance est remise à zéro à
//   chaque rebirth, donc les niveaux qui comptent doivent être atteignables en 2-3 runs.
export const RESISTANCE = {
	maxLevel: 100,
	startPrice: 150,
	priceGrowth: 1.35,
};
```

Mettre aussi à jour l'en-tête du fichier (lignes 7-10), qui décrit encore l'ancien
modèle de prix :

```ts
// Deux formes de courbe de valeur (définies dans ShopConfig, alimentées ici) :
//   • valeur exponentielle : baseValue * valueGrowth ^ level   (BaseCash)
//   • valeur linéaire      : baseValue + level                 (RocketSpeed / Resistance)
//   • prix (chaque stat)   : startPrice * priceGrowth ^ level  (priceGrowth PAR STAT)
```

- [ ] **Step 2 : `ShopConfig.ts` — retirer `PRICE_GROWTH` de l'import**

Ligne 6 : supprimer `PRICE_GROWTH,` de la liste d'import depuis `./ShopBalance`.

- [ ] **Step 3 : `ShopConfig.ts` — ajouter `priceGrowth` à `StatConfig`**

Dans `interface StatConfig`, juste après `readonly startPrice: number;` :

```ts
	readonly priceGrowth: number; // multiplicateur de prix par niveau (propre à la stat)
```

- [ ] **Step 4 : `ShopConfig.ts` — renseigner `priceGrowth` dans les 3 entrées de `STATS`**

```ts
	BaseCash: {
		valueAttribute: "BaseCash",
		levelAttribute: "BaseCashLevel",
		startPrice: BASE_CASH.startPrice,
		priceGrowth: BASE_CASH.priceGrowth,
		valueFor: (level) => math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ** level),
		display: (value) => FormatNumber(value),
	},
	RocketSpeed: {
		valueAttribute: "RocketSpeed",
		levelAttribute: "RocketSpeedLevel",
		startPrice: ROCKET_SPEED.startPrice,
		priceGrowth: ROCKET_SPEED.priceGrowth,
		valueFor: (level) => ROCKET_SPEED.baseValue + level,
		display: (value) => tostring(value),
	},
	Resistance: {
		valueAttribute: "Resistance",
		levelAttribute: "ResistanceLevel",
		startPrice: RESISTANCE.startPrice,
		priceGrowth: RESISTANCE.priceGrowth,
		maxLevel: RESISTANCE.maxLevel,
		valueFor: (level) => level,
		display: (value) => tostring(value),
	},
```

- [ ] **Step 5 : `ShopConfig.ts` — `priceForLevel` lit la croissance de la stat**

```ts
// Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
// serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix.
export function priceForLevel(stat: ShopStat, level: number): number {
	const cfg = STATS[stat];
	return math.floor(cfg.startPrice * cfg.priceGrowth ** level);
}
```

- [ ] **Step 6 : Lancer le simulateur**

```bash
node tools/economy-sim.js
```

Attendu : critères 1 et 1b verts (`premier run 118$`, `upgrade la moins chère 50$`).
Les critères 5, 6, 6b restent en échec (le rebirth n'est pas encore fait).
Le tableau doit montrer des cycles plus longs qu'à la Task 4 — c'est normal, les murs
viennent d'être resserrés.

- [ ] **Step 7 : Vérifier qu'aucun `PRICE_GROWTH` orphelin ne subsiste**

```bash
grep -rn "PRICE_GROWTH" src/
```

Attendu : uniquement les occurrences de `priceGrowth` (minuscule) dans `ShopBalance.ts`
et `ShopConfig.ts`. Aucune occurrence de `PRICE_GROWTH` en majuscules.

- [ ] **Step 8 : Compiler et committer**

```bash
npm run build
git add src/shared/ShopBalance.ts src/shared/ShopConfig.ts out/shared/ShopBalance.luau out/shared/ShopConfig.luau
git commit -m "balance: une croissance de prix par stat, prix de départ revus"
```

---

### Task 6 : Rebirth multiplicatif

**Files:**
- Modify: `src/shared/ShopBalance.ts` (bloc `REBIRTH`)
- Modify: `src/shared/ShopConfig.ts` (`rebirthMult`, `moneyMult`)

**Interfaces:**
- Consumes: `REBIRTH` de `ShopBalance`.
- Produces: `rebirthMult(rebirths: number): number` (signature inchangée, formule géométrique), `moneyMult(multRebirth: number, moneyTierMult: number, inCommunity: boolean): number` (signature inchangée, modèle multiplicatif). `REBIRTH.multTable` et `REBIRTH.multTail` **disparaissent**, remplacés par `REBIRTH.multGrowth`.

- [ ] **Step 1 : `ShopBalance.ts` — remplacer le bloc `REBIRTH`**

```ts
// ── Rebirth ──────────────────────────────────────────────────────────────────
// Remet à zéro l'argent + les 3 niveaux de stat contre un multiplicateur d'argent
// permanent.
//   cost(R) = floor(baseCost * costGrowth ^ R)   (R = rebirths déjà faits)
//   mult(R) = multGrowth ^ R                     (R0 → ×1, R1 → ×8, R2 → ×64…)
//
// multGrowth = 8 est calibré pour que le joueur RETROUVE son revenu de pointe en ~3
// runs après un rebirth (il repart avec BaseCash/RocketSpeed/Resistance à zéro, donc
// un ratio faible le condamnerait à passer la moitié du cycle à racheter l'existant).
// costGrowth = 30 suit la croissance du revenu de pointe d'un cycle à l'autre et
// maintient la boucle autour de 4-8 min. Voir
// docs/superpowers/specs/2026-07-22-progression-rebalance-design.md §4.
export const REBIRTH = {
	baseCost: 20000,
	costGrowth: 30,
	multGrowth: 8,
};
```

- [ ] **Step 2 : `ShopConfig.ts` — `rebirthMult` géométrique**

Remplacer la fonction existante (et son commentaire) par :

```ts
// Multiplicateur d'argent permanent après `rebirths` rebirths. Géométrique : chaque
// rebirth multiplie le précédent par REBIRTH.multGrowth.
export function rebirthMult(rebirths: number): number {
	const r = math.max(0, math.floor(rebirths));
	return REBIRTH.multGrowth ** r;
}
```

- [ ] **Step 3 : `ShopConfig.ts` — `moneyMult` multiplicatif**

Remplacer le bloc de commentaire et la fonction `moneyMult` par :

```ts
// ── Multiplicateurs d'argent — rebirth multiplicatif, boosts additifs ────────────
// Le rebirth MULTIPLIE ; la communauté et le palier de game-pass s'additionnent entre
// eux dans un facteur de boost commun :
//   moneyMult = MultRebirth × (1 + (communauté − 1) + (palier − 1))
// Conséquence voulue : un pass ×2 reste ×2 quel que soit le niveau de rebirth. Avec un
// modèle purement additif, un MultRebirth de 4096 écraserait les paliers MONEY_TIERS
// (un pass ×2 n'ajouterait plus que +1 sur 4096) et les rendrait invendables.
export function moneyMult(multRebirth: number, moneyTierMult: number, inCommunity: boolean): number {
	const communityBonus = inCommunity ? COMMUNITY.mult - 1 : 0;
	const tierBonus = moneyTierMult - 1;
	return multRebirth * (1 + communityBonus + tierBonus);
}
```

- [ ] **Step 4 : Lancer le simulateur — TOUT doit être vert**

```bash
node tools/economy-sim.js
```

Attendu : les 8 lignes de critères en `OK`, le message `Tous les critères sont verts.`
et un exit code 0. Vérifier :

```bash
node tools/economy-sim.js > /dev/null && echo "EXIT 0 — vert"
```

Repères attendus dans le tableau : R1 = 9 runs / 4.5 min / récup. 3 ; R2 = 7 runs /
3.6 min / récup. 3 ; R7 = 13 runs / 7.2 min / récup. 3.

- [ ] **Step 5 : Vérifier qu'aucune référence à `multTable`/`multTail` ne subsiste**

```bash
grep -rn "multTable\|multTail" src/
```

Attendu : aucun résultat.

- [ ] **Step 6 : Compiler et committer**

```bash
npm run build
git add src/shared/ShopBalance.ts src/shared/ShopConfig.ts out/shared/ShopBalance.luau out/shared/ShopConfig.luau
git commit -m "balance: rebirth multiplicatif 8^R, coût 20000 x 30^R, boosts additifs"
```

---

### Task 7 : Le shop affiche l'impact réel

Aujourd'hui le shop affiche la valeur brute de la stat (`3 → 4`), ce qui ne veut rien
dire pour le joueur. Après : BaseCash montre le gain effectif (multiplicateur de rebirth
inclus), RocketSpeed montre le multiplicateur atteint à 10 s de vol, Resistance montre
des **secondes garanties**.

**Files:**
- Modify: `src/shared/RocketGameConfig.ts` (ajout de `multiplierAfter` + `SPEED_PREVIEW_SECONDS`)
- Modify: `src/shared/ShopConfig.ts` (`DisplayContext`, signature de `display`, les 3 rendus, titre Resistance)
- Modify: `src/client/behaviors/ShopItemsController.ts:82-109,131-140`

**Interfaces:**
- Consumes: `resistanceRiskParams` (Task 1/4), `ROCKET_ACCEL`/`ROCKET_MAX_SPEED` (Task 3).
- Produces: `multiplierAfter(speedValue: number, seconds: number): number`, `SPEED_PREVIEW_SECONDS: number`, `interface DisplayContext { readonly moneyMult: number }`, `StatConfig.display: (value: number, ctx: DisplayContext) => string`.

- [ ] **Step 1 : `RocketGameConfig.ts` — ajouter l'aperçu de multiplicateur**

À ajouter à la fin du fichier :

```ts
// Nombre de secondes de vol utilisé par le shop pour prévisualiser l'effet d'un niveau
// de Rocket Speed ("×6.0 à 10 s"). 10 s = le moment où la fusée atteint sa vitesse max.
export const SPEED_PREVIEW_SECONDS = 10;

// Multiplicateur atteint après `seconds` de vol pour une valeur de Rocket Speed donnée.
// Reproduit exactement la boucle serveur (un tick toutes les MULTIPLIER_TICK_RATE
// secondes, chaque tick ajoute vitesse × tick × MULTIPLIER_PER_STUD). Pure — utilisée
// par le shop côté client pour montrer ce qu'achète un niveau.
export function multiplierAfter(speedValue: number, seconds: number): number {
	const accel = ROCKET_ACCEL * speedValue;
	const maxSpeed = ROCKET_MAX_SPEED * speedValue;
	let mult = STARTING_MULTIPLIER;
	for (let t = MULTIPLIER_TICK_RATE; t <= seconds + 1e-6; t += MULTIPLIER_TICK_RATE) {
		mult += math.min(accel * t, maxSpeed) * MULTIPLIER_TICK_RATE * MULTIPLIER_PER_STUD;
	}
	return mult;
}
```

- [ ] **Step 2 : `ShopConfig.ts` — imports**

Ajouter en haut du fichier, après l'import de `FormatNumber` :

```ts
import { resistanceRiskParams } from "./ResistanceCurve";
import { SPEED_PREVIEW_SECONDS, multiplierAfter } from "./RocketGameConfig";
```

- [ ] **Step 3 : `ShopConfig.ts` — `DisplayContext` et la nouvelle signature**

Juste avant `interface StatConfig`, ajouter :

```ts
// Contexte passé au rendu d'une stat. `moneyMult` permet à BaseCash d'afficher le gain
// EFFECTIF (multiplicateur de rebirth et boosts inclus) plutôt que la valeur brute :
// après quelques rebirths, "1K → 1.2K" devient "512K → 614K".
export interface DisplayContext {
	readonly moneyMult: number;
}
```

Dans `interface StatConfig`, remplacer la ligne `display` par :

```ts
	// Rendu lisible par un joueur de la valeur de la stat (pas le nombre brut).
	readonly display: (value: number, ctx: DisplayContext) => string;
```

- [ ] **Step 4 : `ShopConfig.ts` — les 3 rendus**

```ts
	BaseCash: {
		valueAttribute: "BaseCash",
		levelAttribute: "BaseCashLevel",
		startPrice: BASE_CASH.startPrice,
		priceGrowth: BASE_CASH.priceGrowth,
		valueFor: (level) => math.floor(BASE_CASH.baseValue * BASE_CASH.valueGrowth ** level),
		// Gain effectif = ce que le joueur encaisse vraiment (EffectiveBaseCash).
		display: (value, ctx) => `${FormatNumber(math.floor(value * ctx.moneyMult))}$`,
	},
	RocketSpeed: {
		valueAttribute: "RocketSpeed",
		levelAttribute: "RocketSpeedLevel",
		startPrice: ROCKET_SPEED.startPrice,
		priceGrowth: ROCKET_SPEED.priceGrowth,
		valueFor: (level) => ROCKET_SPEED.baseValue + level,
		// "3 (x6)" — la vitesse brute plus le multiplicateur atteint à 10 s de vol.
		display: (value) => `${value} (x${trimDecimals(multiplierAfter(value, SPEED_PREVIEW_SECONDS))})`,
	},
	Resistance: {
		valueAttribute: "Resistance",
		levelAttribute: "ResistanceLevel",
		startPrice: RESISTANCE.startPrice,
		priceGrowth: RESISTANCE.priceGrowth,
		maxLevel: RESISTANCE.maxLevel,
		valueFor: (level) => level,
		// Secondes de vol garanties — la seule formulation compréhensible de cette stat.
		display: (value) => `${string.format("%.1f", resistanceRiskParams(value).safeWindow)}s`,
	},
```

- [ ] **Step 5 : `ShopConfig.ts` — retitrer l'item Resistance**

Dans `ITEMS`, remplacer le titre de `Resistance` :

```ts
	Resistance: { id: "Resistance", stat: "Resistance", quantity: 1, frameName: "DSafety", title: "Vol garanti" },
```

- [ ] **Step 6 : `ShopItemsController.ts` — lire `MoneyMult` et le passer au rendu**

Après `getMoney()` (ligne 39-41), ajouter :

```ts
// Multiplicateur d'argent répliqué (rebirth × boosts) — sert à afficher le gain
// EFFECTIF de BaseCash au lieu de sa valeur brute.
function getMoneyMult(): number {
	return (player.GetAttribute("MoneyMult") as number | undefined) ?? 1;
}
```

Dans `refresh()`, remplacer les deux appels à `cfg.display(...)` :

```ts
	function refresh(): void {
		const level = getLevel(cfg.levelAttribute);
		const ctx = { moneyMult: getMoneyMult() };
		currentText.Text = cfg.display(cfg.valueFor(level), ctx);

		if (isAtCap(item.stat, level)) {
			nextText.Text = "MAX";
			priceLabel.Text = "MAX";
			setAffordable(buyButton, priceLabel, false);
			if (product) {
				robuxGainLabel.Text = "MAX";
				robuxButton.AutoButtonColor = false;
				robuxButton.BackgroundTransparency = 0.6;
			}
			return;
		}

		nextText.Text = cfg.display(cfg.valueFor(level + item.quantity), ctx);
		const price = priceForItem(item, level);
		priceLabel.Text = `${FormatNumber(price)}$`;
		setAffordable(buyButton, priceLabel, getMoney() >= price);
		if (product) {
			robuxGainLabel.Text = `+${product.levels} niv.`;
			robuxButton.AutoButtonColor = true;
			robuxButton.BackgroundTransparency = 0;
		}
	}
```

- [ ] **Step 7 : `ShopItemsController.ts` — rafraîchir sur `MoneyMult`**

Dans `init()`, ajouter après la ligne `player.GetAttributeChangedSignal("ResistanceLevel").Connect(refreshAll);` :

```ts
	// Un rebirth change MoneyMult → le gain effectif affiché sur BaseCash doit suivre.
	player.GetAttributeChangedSignal("MoneyMult").Connect(refreshAll);
```

- [ ] **Step 8 : Compiler**

```bash
npm run build
```

Attendu : aucune erreur. Une erreur `Expected 1 arguments, but got 2` signale un appel à
`display()` oublié ailleurs — chercher avec `grep -rn "\.display(" src/`.

- [ ] **Step 9 : Vérifier en jeu (Studio)**

Ouvrir Studio, lancer une partie, ouvrir le shop. Attendu :
- **Button money** : `100$ → 120$` au niveau 0 sans rebirth ; après 1 rebirth, `800$ → 960$`.
- **Rocket speed** : `1 (x2.65) → 2 (x4.3)`.
- **Vol garanti** : `0.0s → 1.0s` au niveau 0, `1.0s → 1.8s` au niveau 1.

- [ ] **Step 10 : Commit**

```bash
npm run build
git add src/shared/RocketGameConfig.ts src/shared/ShopConfig.ts src/client/behaviors/ShopItemsController.ts out/shared/RocketGameConfig.luau out/shared/ShopConfig.luau out/client/behaviors/ShopItemsController.luau
git commit -m "feat(shop): afficher l'impact réel des upgrades (gain effectif, multiplicateur, secondes garanties)"
```

---

### Task 8 : Readout du multiplicateur cohérent avec le modèle multiplicatif

Le readout du header du shop décrit encore une somme (`Rebirth ×8 · Communauté ×2 ·
Palier ×4`), ce qui ne correspond plus au calcul.

**Files:**
- Modify: `src/client/behaviors/BoostShopController.ts:29-36`

**Interfaces:**
- Consumes: les attributs répliqués `MoneyMult`, `MultRebirth`, `MoneyTierMult`, `InCommunity`.
- Produces: rien (affichage seul).

- [ ] **Step 1 : Remplacer `refresh()`**

```ts
	function refresh(): void {
		const rebirth = num("MultRebirth", 1);
		const tier = num("MoneyTierMult", 1);
		const inCommunity = player.GetAttribute("InCommunity") === true;
		const total = num("MoneyMult", 1);
		// Le rebirth MULTIPLIE le facteur de boost ; la communauté et le palier
		// s'additionnent à l'intérieur de ce facteur (voir ShopConfig.moneyMult).
		const boosts = 1 + (inCommunity ? 1 : 0) + (tier - 1);
		readout.Text = `Money ${fmtMult(total)} (Rebirth ${fmtMult(rebirth)} × Boosts ${fmtMult(boosts)})`;
	}
```

- [ ] **Step 2 : Compiler**

```bash
npm run build
```

- [ ] **Step 3 : Vérifier la cohérence arithmétique en jeu**

Dans Studio, ouvrir le shop. Le nombre après `Money` doit être exactement le produit des
deux autres. Sans rebirth ni boost : `Money ×1 (Rebirth ×1 × Boosts ×1)`. Après un
rebirth : `Money ×8 (Rebirth ×8 × Boosts ×1)`.

- [ ] **Step 4 : Commit**

```bash
git add src/client/behaviors/BoostShopController.ts out/client/behaviors/BoostShopController.luau
git commit -m "fix(shop): readout du multiplicateur aligné sur le modèle multiplicatif"
```

---

### Task 9 : Pulse du bouton Claim

Le `ClaimButton` pulse tant que le joueur n'a pas claim 3 fois dans la session. Compteur
en mémoire côté client : aucun état serveur, aucun champ DataStore, aucun événement
réseau, aucune instance à créer dans Studio (le halo est un `UIStroke` créé en code).

**Files:**
- Modify: `src/client/behaviors/RocketLaunchBehavior.ts` (état module, helpers, `setup()`, `fireClaim`, `fireGoHome`, handler `PlayerKilledEvent`)

**Interfaces:**
- Consumes: `claimButton`, `buttonOriginalSize` (déjà présents dans le fichier), `TweenService` (déjà importé ligne 16).
- Produces: rien d'exporté.

- [ ] **Step 1 : État module**

Après la ligne 38 (`let multiplierTextOriginalColor: Color3 | undefined;`), ajouter :

```ts
// Pulse d'onboarding du bouton Claim : tant que le joueur n'a pas encaissé quelques
// fois, le bouton respire (taille + halo) pour que le geste soit impossible à rater.
// Compteur en mémoire, remis à zéro à chaque session — aucun état serveur.
let claimPulseTween: Tween | undefined;
let claimPulseStroke: UIStroke | undefined;
let claimPulseStrokeTween: Tween | undefined;
let sessionClaimCount = 0;
```

- [ ] **Step 2 : Constantes**

Juste après `const CLAIM_REARM_DELAY = 0.6;` (ligne 164), ajouter :

```ts
// Nombre de claims après lequel le pulse d'onboarding s'arrête définitivement (session).
const CLAIM_PULSE_RUNS = 3;
// Amplitude du gonflement du bouton pendant le pulse.
const CLAIM_PULSE_SCALE = 1.08;
const ClaimPulseTI = new TweenInfo(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true);
```

- [ ] **Step 3 : Helpers `startClaimPulse` / `stopClaimPulse`**

À ajouter juste avant `export function setup(` (ligne 415) :

```ts
// Arrête le pulse et remet le bouton à sa taille / son halo d'origine. Idempotent :
// appelable même si aucun pulse ne tourne.
function stopClaimPulse(): void {
	claimPulseTween?.Cancel();
	claimPulseTween = undefined;
	claimPulseStrokeTween?.Cancel();
	claimPulseStrokeTween = undefined;
	if (claimPulseStroke) claimPulseStroke.Enabled = false;
	if (claimButton && buttonOriginalSize) claimButton.Size = buttonOriginalSize;
}

// Fait respirer le bouton tant que le joueur n'a pas encaissé CLAIM_PULSE_RUNS fois.
// À appeler APRÈS la restauration de claimButton.Size dans setup(), sinon la taille
// d'origine serait écrasée par une frame de pulse.
function startClaimPulse(): void {
	if (sessionClaimCount >= CLAIM_PULSE_RUNS) return;
	if (!claimButton || !buttonOriginalSize) return;

	// Halo créé une seule fois, en code — rien à ajouter dans Studio.
	if (!claimPulseStroke) {
		const stroke = new Instance("UIStroke");
		stroke.Name = "ClaimPulseStroke";
		stroke.Thickness = 4;
		stroke.Color = new Color3(1, 1, 1);
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		stroke.Parent = claimButton;
		claimPulseStroke = stroke;
	}
	claimPulseStroke.Enabled = true;
	claimPulseStroke.Transparency = 0.8;

	const s = buttonOriginalSize;
	const grown = new UDim2(
		s.X.Scale * CLAIM_PULSE_SCALE,
		s.X.Offset * CLAIM_PULSE_SCALE,
		s.Y.Scale * CLAIM_PULSE_SCALE,
		s.Y.Offset * CLAIM_PULSE_SCALE,
	);
	claimPulseTween = TweenService.Create(claimButton, ClaimPulseTI, { Size: grown });
	claimPulseTween.Play();
	claimPulseStrokeTween = TweenService.Create(claimPulseStroke, ClaimPulseTI, { Transparency: 0.1 });
	claimPulseStrokeTween.Play();
}
```

- [ ] **Step 4 : Démarrer le pulse dans `setup()`**

Après le bloc de restauration du bouton (lignes 479-484, celui qui se termine par
`claimButton.Visible = true;`), ajouter :

```ts
	// Onboarding : le bouton respire tant que le joueur n'a pas encaissé quelques fois.
	// Doit venir APRÈS la restauration de Size ci-dessus.
	stopClaimPulse();
	startClaimPulse();
```

- [ ] **Step 5 : Arrêter le pulse au claim et compter**

Dans `fireClaim`, juste après `hasClaimed = true;` :

```ts
		sessionClaimCount += 1;
		stopClaimPulse();
```

- [ ] **Step 6 : Arrêter le pulse aux deux autres fins de partie**

Dans `fireGoHome`, juste après `isGoHomeMode = false;` :

```ts
		stopClaimPulse();
```

Dans le handler `Events.PlayerKilledEvent.OnClientEvent` (ligne 291), juste après
`isGoHomeMode = false;` (ligne 297) :

```ts
		stopClaimPulse(); // fin de partie : plus de respiration sur un bouton éteint
```

- [ ] **Step 7 : Compiler**

```bash
npm run build
```

- [ ] **Step 8 : Vérifier en jeu (Studio)**

1. Lancer une partie → le bouton Claim doit respirer (taille + halo blanc).
2. Cliquer Claim → le pulse s'arrête net, le bouton devient rouge à sa taille normale.
3. Relancer 2 parties en claimant à chaque fois → au 4ᵉ lancement le bouton **ne pulse
   plus** (`sessionClaimCount` = 3).
4. Relancer une partie et laisser exploser sans claim → le pulse s'arrête à l'explosion
   et le bouton est rouge à sa taille normale (pas gonflé).
5. Vérifier qu'un seul `UIStroke` nommé `ClaimPulseStroke` existe sous le `ClaimButton`
   après plusieurs parties (le halo est créé une seule fois).

- [ ] **Step 9 : Commit**

```bash
git add src/client/behaviors/RocketLaunchBehavior.ts out/client/behaviors/RocketLaunchBehavior.luau
git commit -m "feat(ui): pulse d'onboarding sur le bouton Claim (3 premiers claims de la session)"
```

---

### Task 10 : Synchroniser `ARCHITECTURE.md`

**Files:**
- Modify: `ARCHITECTURE.md` (§3 arborescence, §6.3, §6.6, §6.8, §6.9)

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: rien.

- [ ] **Step 1 : §3 — ajouter le nouveau module shared**

Dans l'arborescence `src/shared/`, après la ligne `RocketGameConfig.ts`, ajouter :

```
    ├── ResistanceCurve.ts   # Resistance → {riskScale, safeWindow} (partagé serveur/shop)
```

Et à la racine du dépôt, mentionner `tools/economy-sim.js`.

- [ ] **Step 2 : §6.3 — corriger la description de la boucle de risque**

Le paragraphe « Risk loop » affirme que les constantes vivent en haut de
`ButtonInGameModule.ts` et que `riskScale` est le levier principal. Le remplacer par une
description exacte : les constantes et `resistanceRiskParams` vivent dans
`shared/ResistanceCurve.ts` ; `safeWindow` est **front-loaded** et constitue le levier
principal (montré au joueur en secondes) ; `riskScale` est secondaire (survie en
`riskScale^(-1/3)`) ; à resistance 0 la courbe est inchangée.

Corriger aussi la phrase sur `MULTIPLIER_PER_STUD` / Rocket Speed : au niveau 0 la fusée
ne « rampe » plus, elle atteint 30 studs/s en 10 s (×2.65 de multiplicateur).

- [ ] **Step 3 : §6.6 — corriger la formule de `MoneyMult`**

Remplacer la description du « additive bonus model » par le modèle appliqué :
`MoneyMult = MultRebirth × (1 + (communauté − 1) + (palier − 1))`, avec la raison (un
pass ×2 reste ×2 à tout niveau de rebirth). `EffectiveBaseCash = floor(BaseCash ×
MoneyMult)` est inchangé.

- [ ] **Step 4 : §6.8 — corriger les courbes et l'affichage du shop**

- Courbes : BaseCash `floor(100 × 1.2^level)`, RocketSpeed `1 + level`, Resistance
  `level` (maxLevel 100). Prix de départ **50 / 75 / 150**, croissance de prix **par
  stat** (1.8 / 1.7 / 1.35) — `PRICE_GROWTH` global supprimé.
- `ShopItemsController` affiche désormais l'impact : gain effectif en `$` pour BaseCash
  (lit `MoneyMult`), `valeur (xN)` pour RocketSpeed, **secondes garanties** pour
  Resistance (titre « Vol garanti »).
- `BoostShopController` : readout `Money ×T (Rebirth ×R × Boosts ×B)`.

- [ ] **Step 5 : §6.9 — corriger le coût et la récompense du rebirth**

`rebirthCost(R) = floor(20 000 × 30^R)` et `rebirthMult(R) = 8^R` (la table
`[1,2,3,3.5,…]` et `multTail` n'existent plus).

- [ ] **Step 6 : Relire la cohérence**

```bash
grep -n "2500\|2.4\^R\|multTable\|PRICE_GROWTH\|additive bonus" ARCHITECTURE.md
```

Attendu : aucun résultat. Toute occurrence restante décrit l'ancien équilibrage.

- [ ] **Step 7 : Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: synchroniser ARCHITECTURE.md avec le rééquilibrage progression & rebirth"
```

---

## Vérification finale

- [ ] `node tools/economy-sim.js` → exit 0, tous les critères verts.
- [ ] `npm run build` → aucune erreur.
- [ ] En jeu : premier run ≥ 100$, un achat possible dès le retour au shop.
- [ ] En jeu : le shop affiche des secondes pour « Vol garanti » et un montant en `$` pour « Button money ».
- [ ] En jeu : le bouton Claim pulse au premier lancement et s'arrête après 3 claims.
- [ ] En jeu : faire un rebirth → `MoneyMult` passe à ×8, le shop repart à zéro, et le revenu de pointe précédent est retrouvé en ~3 runs.
