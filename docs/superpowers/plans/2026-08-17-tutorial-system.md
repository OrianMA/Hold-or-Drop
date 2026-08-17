# Tutorial System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un système de tutorial isolé qui guide le premier run d'un joueur (flèches, mise en avant, run truqué), persiste sa progression et se mesure en analytics — sans altérer le jeu de base.

**Architecture:** Serveur = source de vérité de l'étape courante (attribut répliqué `TutorialStep`, store dédié `PlayerTutorial_v1`) et metteur en scène du run truqué. Client = tout le rendu (traînée de flèches, dim/highlight, bandeau) et la détection des complétions, remontées par un seul RemoteEvent. Le jeu de base ne gagne que quelques one-liners listés au §13 du spec.

**Tech Stack:** roblox-ts (`rbxtsc`), Rojo, DataStore, Roblox AnalyticsService. Aucune dépendance ajoutée.

**Spec de référence :** `docs/superpowers/specs/2026-08-17-tutorial-system-design.md` — à relire avant chaque tâche.

## Global Constraints

- Branche **`Tutorial`**. **Aucun merge, aucune PR, aucun push** — le dev s'en charge.
- **Pas de framework de test** dans ce projet. Le cycle rouge/vert est : (1) une sonde de vérification (Luau via le MCP `Roblox_Studio`, ou `node tools/economy-sim.js`) qui **échoue d'abord**, (2) l'implémentation, (3) la même sonde qui passe. Ne jamais annoncer « ça marche » sans avoir montré la sortie.
- `npm run build` doit être **silencieux** (aucune sortie = succès). Toute erreur TS bloque la tâche.
- `out/` est généré et suivi par git : après un build, **stager uniquement les fichiers `out/` correspondant aux sources touchées** (`git add out/server/tutorial` etc.), jamais `git add -A` — le build réécrit tout le dossier en CRLF et noierait le diff.
- Studio : un seul instance connectée, id obtenu via `list_roblox_studios`. Les méthodes compilées s'appellent avec **`:`** et non `.` (paramètre `self`) : `RoomService:getRoom(player)`.
- Typage strict, pas de `any`. Commentaires FR ou EN selon le fichier voisin (le code tuto est commenté en FR).
- `CheatConfig` : toute nouvelle constante de cheat est à **`false`** dans le commit.
- Image de flèche : **`rbxassetid://104204322044198`**.
- Hiérarchie Studio du Skip (déjà authorée, ne pas la créer) : `InGameUI/TutorialSkip/TutorialSkipFrame/TextButton`.

---

## File Structure

**Créés — shared (contrats lus des deux côtés)**
- `src/shared/tutorial/TutorialTypes.ts` — types purs : Step, Target, Trigger, ScriptedRun.
- `src/shared/tutorial/TutorialSteps.ts` — la liste ordonnée des 8 steps + helpers d'index.

**Créés — serveur**
- `src/server/tutorial/TutorialService.ts` — état par joueur, avancement, persistance, attribut, cheats.
- `src/server/tutorial/TutorialAnalytics.ts` — sémantique analytics (funnel + 4 compteurs).
- `src/server/tutorial/TutorialRunDirector.ts` — met en scène le run truqué (gel, reprise, explosion).
- `src/server/tutorial/TutorialHooks.ts` — la seule API que le jeu de base appelle.

**Créés — client**
- `src/client/tutorial/TutorialUI.ts` — le ScreenGui `TutorialUI` + le bandeau d'instruction.
- `src/client/tutorial/TutorialSkipButton.ts` — pilote le bouton Studio.
- `src/client/tutorial/TutorialTargets.ts` — résolution d'une cible (GUI path / monde) en instance.
- `src/client/tutorial/TutorialTriggers.ts` — surveille la condition de complétion d'un step.
- `src/client/tutorial/TutorialArrow.ts` — traînée de flèches monde + flèche écran + chevron.
- `src/client/tutorial/TutorialFocus.ts` — dim « troué » / highlight.
- `src/client/tutorial/TutorialGate.ts` — verrouillage des boutons et des prompts hors-scope.
- `src/client/tutorial/TutorialController.ts` — orchestre tout ce qui précède.

**Modifiés — jeu de base (minimal)**
- `src/shared/Event.ts` — `TutorialAdvanceEvent`.
- `src/shared/ShopBalance.ts` / `src/shared/ShopConfig.ts` — prix des 2 premiers RocketSpeed.
- `tools/economy-sim.js` — lit et applique `firstLevelPrices`.
- `src/server/modules/RocketLauncher.ts` — `freeze` / `unfreeze` / `isFrozen`.
- `src/server/modules/ButtonInGameModule.ts` — 3 lignes de hook.
- `src/server/modules/CheatConfig.ts` — `forceTutorial`.
- `src/server/services/AnalyticsService.ts` — helper générique `funnelStep`.
- `src/server/services/index.ts` — `TutorialService` dans la liste de boot.
- `src/client/main.client.ts` — `initTutorial()`.
- `src/client/behaviors/RocketLaunchBehavior.ts` — pulse Claim en veille pendant le tuto.
- `ARCHITECTURE.md` — nouvelle section + corrections.

---

## Task 1: Types et liste des steps (shared)

**Files:**
- Create: `src/shared/tutorial/TutorialTypes.ts`
- Create: `src/shared/tutorial/TutorialSteps.ts`

**Interfaces:**
- Consumes: rien.
- Produces: `TutorialStep`, `TutorialTarget`, `TutorialTrigger`, `TutorialFocus`, `ScriptedRun`, `WorldTargetId`, `PopupOrMenuName`, `TutorialWatchableEvent`, `TUTORIAL_STEPS: readonly TutorialStep[]`, `stepIndexById(id: string): number | undefined`, `stepById(id: string): TutorialStep | undefined`, `firstStepId(): string`.

- [ ] **Step 1: Créer les types**

`src/shared/tutorial/TutorialTypes.ts` :

```ts
// Types du système de tutorial. Données pures : aucun import serveur/client, pour que
// les deux côtés lisent la même liste de steps (shared/tutorial/TutorialSteps.ts).

// Cibles monde adressables par un step (résolues côté client).
export type WorldTargetId = "RoomButton" | "Shop";

// Frames de InGameUI dont l'ouverture/fermeture peut valider un step.
export type PopupOrMenuName = "ButtonMenu" | "RocketLaunch" | "ButtonFinishGame" | "ShopMenu";

// Events serveur → client existants que le client sait déjà écouter.
export type TutorialWatchableEvent = "ButtonTrigger" | "ClaimAccepted";

export type TutorialTarget =
	| { readonly kind: "gui"; readonly path: string } // chemin sous InGameUI, ex "ButtonMenu/StartButton"
	| { readonly kind: "world"; readonly part: WorldTargetId }
	| { readonly kind: "none" };

// Comment la cible est mise en avant :
//   "dim"       → overlay sombre troué + blocage (menus : la vue 3D n'a pas d'importance)
//   "highlight" → contour pulsé, SANS assombrir (steps en vol : la fusée doit rester visible)
//   absent      → aucune mise en avant (steps monde : on pointe, on ne masque rien)
export type TutorialFocus = "dim" | "highlight";

export type TutorialTrigger =
	| { readonly kind: "event"; readonly event: TutorialWatchableEvent }
	// Le step passe quand l'attribut a AUGMENTÉ de `increaseBy` depuis l'entrée dans le step
	// (et non quand il atteint une valeur absolue : un joueur existant a déjà des niveaux).
	| { readonly kind: "attribute"; readonly attribute: string; readonly increaseBy: number }
	| { readonly kind: "popup"; readonly popup: PopupOrMenuName } // devient visible
	| { readonly kind: "popupClosed"; readonly popup: PopupOrMenuName } // redevient invisible
	| { readonly kind: "server" }; // le serveur sort lui-même de ce step (run truqué)

// Scénario imposé au run lancé depuis un step. Lu UNE fois, au décollage.
export interface ScriptedRun {
	readonly freezeAt?: number; // gèle l'ascension à t secondes
	readonly advanceToOnFreeze?: string; // step id vers lequel sauter au gel (déterministe)
	readonly unfreezeOnClaim?: boolean; // le claim relance l'ascension
	readonly explodeAfterClaim?: number; // explosion N secondes après le claim
	readonly explodeAt?: number; // explosion à t fixe depuis le décollage
	readonly noRisk?: boolean; // aucun tirage aléatoire : seul le script peut faire exploser
}

export interface TutorialStep {
	readonly id: string; // stable — c'est LUI qui est persisté
	readonly text: string; // instruction affichée (FR)
	readonly target: TutorialTarget;
	readonly focus?: TutorialFocus;
	readonly run?: ScriptedRun;
	readonly complete: TutorialTrigger;
}
```

- [ ] **Step 2: Créer la liste des steps**

`src/shared/tutorial/TutorialSteps.ts` :

```ts
import { TutorialStep } from "./TutorialTypes";

// LA liste du tutorial, dans l'ordre. Éditer ici pour changer le déroulé.
// L'`id` est la clé persistée : le renommer renvoie au début les joueurs qui y étaient.
// Voir docs/superpowers/specs/2026-08-17-tutorial-system-design.md §10.
export const TUTORIAL_STEPS: readonly TutorialStep[] = [
	{
		id: "go-to-button",
		text: "Va appuyer sur ton bouton !",
		target: { kind: "world", part: "RoomButton" },
		complete: { kind: "event", event: "ButtonTrigger" },
	},
	{
		id: "press-start",
		text: "Appuie sur START pour faire décoller ta fusée",
		target: { kind: "gui", path: "ButtonMenu/StartButton" },
		focus: "dim",
		// Le run truqué est porté par le step DEPUIS lequel le décollage part.
		run: {
			freezeAt: 2.5,
			advanceToOnFreeze: "claim",
			unfreezeOnClaim: true,
			explodeAfterClaim: 1,
			noRisk: true,
		},
		complete: { kind: "popup", popup: "RocketLaunch" },
	},
	{
		id: "watch-launch",
		text: "Ta fusée décolle ! Plus elle monte, plus ton multiplicateur grimpe",
		target: { kind: "none" },
		complete: { kind: "server" }, // le director saute à "claim" au gel (2,5 s)
	},
	{
		id: "claim",
		text: "Appuie sur CLAIM pour sécuriser tes gains",
		target: { kind: "gui", path: "RocketLaunch/ClaimButtonFrame/ClaimButton" },
		focus: "highlight", // pas de dim : la fusée doit rester visible
		complete: { kind: "event", event: "ClaimAccepted" },
	},
	{
		id: "claim-explode",
		text: "Gains sécurisés ! Même si la fusée explose, tu gardes tout",
		target: { kind: "none" },
		complete: { kind: "popupClosed", popup: "ButtonFinishGame" },
	},
	{
		id: "go-to-shop",
		text: "Direction la boutique pour améliorer ta fusée",
		target: { kind: "world", part: "Shop" },
		complete: { kind: "popup", popup: "ShopMenu" },
	},
	{
		id: "buy-rocket-speed",
		text: "Achète Rocket Speed : ta fusée montera plus vite",
		target: { kind: "gui", path: "ShopMenu/Body/ARocketSpeed" },
		focus: "dim",
		complete: { kind: "attribute", attribute: "RocketSpeedLevel", increaseBy: 1 },
	},
	{
		id: "back-to-button",
		text: "Retourne à ton bouton et rejoue — à toi de jouer !",
		target: { kind: "world", part: "RoomButton" },
		complete: { kind: "event", event: "ButtonTrigger" },
	},
];

export function stepIndexById(id: string): number | undefined {
	for (let i = 0; i < TUTORIAL_STEPS.size(); i++) {
		if (TUTORIAL_STEPS[i].id === id) return i;
	}
	return undefined;
}

export function stepById(id: string): TutorialStep | undefined {
	const index = stepIndexById(id);
	return index !== undefined ? TUTORIAL_STEPS[index] : undefined;
}

export function firstStepId(): string {
	return TUTORIAL_STEPS[0].id;
}
```

- [ ] **Step 3: Vérifier la compilation**

Run: `npm run build`
Expected: aucune sortie (succès). Les deux fichiers apparaissent dans `out/shared/tutorial/`.

- [ ] **Step 4: Vérifier la cohérence de la liste**

Run:
```bash
node -e "const s=require('fs').readFileSync('out/shared/tutorial/TutorialSteps.luau','utf8');const ids=[...s.matchAll(/id = \"([a-z-]+)\"/g)].map(m=>m[1]);console.log(ids.join(' -> '));console.log('advanceToOnFreeze cible existante:', s.includes('advanceToOnFreeze = \"claim\"') && ids.includes('claim'));"
```
Expected: `go-to-button -> press-start -> watch-launch -> claim -> claim-explode -> go-to-shop -> buy-rocket-speed -> back-to-button` puis `advanceToOnFreeze cible existante: true`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/tutorial out/shared/tutorial
git commit -m "feat(tutorial): types et liste des 8 steps"
```

---

## Task 2: Prix des 2 premiers niveaux de Rocket Speed

**Files:**
- Modify: `src/shared/ShopBalance.ts` (bloc `ROCKET_SPEED`)
- Modify: `src/shared/ShopConfig.ts` (`StatConfig`, `STATS.RocketSpeed`, `priceForLevel`)
- Modify: `tools/economy-sim.js`

**Interfaces:**
- Consumes: rien.
- Produces: `ROCKET_SPEED.firstLevelPrices: readonly number[]`, `StatConfig.firstLevelPrices?: readonly number[]`, `priceForLevel(stat, level)` inchangée en signature.

- [ ] **Step 1: Écrire l'assertion qui échoue dans le simulateur**

Ouvrir `tools/economy-sim.js`, repérer la section des constantes (`C.RS_PRICE`, ~ligne 87) et la fonction qui calcule un prix de niveau. Ajouter juste après la lecture des constantes :

```js
// Prix imposés des premiers niveaux (ShopBalance.ROCKET_SPEED.firstLevelPrices) — un
// tableau d'exceptions consulté avant la formule, pour que l'onboarding soit abordable.
function firstLevelPricesOf(block) {
	const src = S_BAL.match(
		new RegExp(`export const ${block}[\\s\\S]*?firstLevelPrices:\\s*\\[([^\\]]*)\\]`),
	);
	if (!src) return [];
	return src[1]
		.split(",")
		.map((n) => Number(n.trim()))
		.filter((n) => Number.isFinite(n));
}
C.RS_FIRST_PRICES = firstLevelPricesOf("ROCKET_SPEED");

// Vérifie l'invariant d'onboarding : les 2 premiers niveaux de Rocket Speed doivent
// tenir dans le gain du premier run guidé (~109 $, voir le spec tutorial §10).
function assertOnboardingPrices() {
	const p0 = C.RS_FIRST_PRICES[0];
	const p1 = C.RS_FIRST_PRICES[1];
	if (p0 === undefined || p1 === undefined) {
		throw new Error("ROCKET_SPEED.firstLevelPrices doit définir les 2 premiers niveaux");
	}
	if (p0 + p1 > 109) {
		throw new Error(`Les 2 premiers Rocket Speed coûtent ${p0 + p1} $ > 109 $ (run guidé)`);
	}
	console.log(`OK onboarding: Rocket Speed L1=${p0}$ L2=${p1}$ (total ${p0 + p1}$ <= 109$)`);
}
assertOnboardingPrices();
```

Puis apprendre les overrides au helper de prix. **Ligne 119**, remplacer :

```js
const price = (start, growth, lvl) => Math.floor(start * growth ** lvl);
```
par :

```js
// `overrides` = prix imposés par niveau (ShopConfig.priceForLevel fait pareil côté jeu).
const price = (start, growth, lvl, overrides) => {
	const forced = overrides?.[lvl];
	if (forced !== undefined) return forced;
	return Math.floor(start * growth ** lvl);
};
```

**Ligne ~211**, l'option d'achat RocketSpeed devient :

```js
				{ p: price(C.RS_PRICE, C.RS_PRICE_GROWTH, Ls, C.RS_FIRST_PRICES), e: ev(Lb, Ls + 1, Lr, R).ev, f: () => Ls++ },
```

**Ligne ~259**, le critère « achat possible dès le run 1 » doit comparer au vrai prix du premier niveau :

```js
const cheapest = Math.min(C.BC_PRICE, price(C.RS_PRICE, C.RS_PRICE_GROWTH, 0, C.RS_FIRST_PRICES), C.RES_PRICE);
```

- [ ] **Step 2: Lancer le simulateur pour voir l'échec**

Run: `node tools/economy-sim.js`
Expected: échec — `Error: ROCKET_SPEED.firstLevelPrices doit définir les 2 premiers niveaux` (le champ n'existe pas encore).

- [ ] **Step 3: Ajouter le champ dans ShopBalance**

Dans `src/shared/ShopBalance.ts`, remplacer le bloc `ROCKET_SPEED` par :

```ts
export const ROCKET_SPEED = {
	baseValue: 1,
	startPrice: 75,
	priceGrowth: 1.7,
	// Prix IMPOSÉS des premiers niveaux (index = niveau de départ). Au-delà du tableau,
	// la courbe startPrice * priceGrowth ^ level reprend telle quelle (L2→3 = 216 $).
	// Onboarding : les 2 premières améliorations doivent tenir dans le gain du premier
	// run guidé (~109 $) — voir le spec tutorial §11.
	firstLevelPrices: [25, 50] as readonly number[],
};
```

- [ ] **Step 4: Brancher l'override dans ShopConfig**

Dans `src/shared/ShopConfig.ts`, ajouter le champ à `StatConfig` (juste après `priceGrowth`) :

```ts
	readonly priceGrowth: number; // multiplicateur de prix par niveau (propre à la stat)
	// Prix imposés des premiers niveaux (index = niveau de départ) ; au-delà, la formule
	// reprend. Sert l'onboarding — voir ShopBalance.ROCKET_SPEED.firstLevelPrices.
	readonly firstLevelPrices?: readonly number[];
```

Ajouter la ligne dans `STATS.RocketSpeed` (après `priceGrowth: ROCKET_SPEED.priceGrowth,`) :

```ts
		firstLevelPrices: ROCKET_SPEED.firstLevelPrices,
```

Et remplacer `priceForLevel` par :

```ts
// Prix pour passer de `level` à `level + 1`. Entier déterministe pour que client et
// serveur soient toujours d'accord. Chaque stat a sa propre croissance de prix, et peut
// imposer les prix de ses premiers niveaux (firstLevelPrices).
export function priceForLevel(stat: ShopStat, level: number): number {
	const cfg = STATS[stat];
	const override = cfg.firstLevelPrices?.[level];
	if (override !== undefined) return override;
	return math.floor(cfg.startPrice * cfg.priceGrowth ** level);
}
```

- [ ] **Step 5: Relancer le simulateur — il doit passer**

Run: `node tools/economy-sim.js`
Expected: `OK onboarding: Rocket Speed L1=25$ L2=50$ (total 75$ <= 109$)` puis la sortie habituelle du simulateur **sans aucun critère en échec**. Si un critère de balance casse, ne pas le contourner : le signaler dans le rapport de tâche.

- [ ] **Step 6: Vérifier la compilation**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 7: Commit**

```bash
git add src/shared/ShopBalance.ts src/shared/ShopConfig.ts tools/economy-sim.js out/shared/ShopBalance.luau out/shared/ShopConfig.luau
git commit -m "balance: Rocket Speed L1/L2 a 25/50\$ pour l'onboarding"
```

---

## Task 3: `RocketLauncher.freeze` / `unfreeze`

**Files:**
- Modify: `src/server/modules/RocketLauncher.ts`

**Interfaces:**
- Consumes: rien.
- Produces: `RocketLauncher.freeze(room: Room): void`, `RocketLauncher.unfreeze(room: Room): void`, `RocketLauncher.isFrozen(room: Room): boolean`. `getVelocity(room)` renvoie désormais `0` quand la fusée est gelée.

- [ ] **Step 1: Écrire la sonde Studio (elle doit échouer)**

Lancer le jeu : MCP `start_stop_play` (single-player), attendre le spawn. Puis MCP `execute_luau` avec `datamodel_type: "Server"` :

```lua
local Players = game:GetService("Players")
local TS = game:GetService("ServerScriptService"):WaitForChild("TS")
local RoomService = require(TS.rooms.RoomService).RoomService
local RocketLauncher = require(TS.modules.RocketLauncher).RocketLauncher

local player = Players:GetPlayers()[1]
local room = RoomService:getRoom(player)
assert(room, "aucune room assignée")

RocketLauncher:launch(room, 1)
task.wait(2)
local yBefore = room.movableModel:GetPivot().Position.Y
local vBefore = RocketLauncher:getVelocity(room)

RocketLauncher:freeze(room)
task.wait(1)
local yFrozen = room.movableModel:GetPivot().Position.Y
local vFrozen = RocketLauncher:getVelocity(room)

RocketLauncher:unfreeze(room)
task.wait(1)
local yResumed = room.movableModel:GetPivot().Position.Y
RocketLauncher:reset(room)

return string.format(
	"monte=%s | gel_immobile=%s | velocite_gelee_nulle=%s | reprise=%s",
	tostring(yBefore > 0.5),
	tostring(math.abs(yFrozen - yBefore) < 0.2),
	tostring(vFrozen == 0),
	tostring(yResumed > yFrozen + 1)
)
```

Expected: **échec** — `attempt to call a nil value` sur `RocketLauncher:freeze`.

- [ ] **Step 2: Ajouter l'état `paused`**

Dans `src/server/modules/RocketLauncher.ts`, ajouter le champ à `RocketState` (après `velocity: number;`) :

```ts
	// Vol gelé sur place (tutorial) : la boucle d'ascension ne bouge plus mais la
	// vélocité acquise est CONSERVÉE pour la reprise. getVelocity renvoie 0 pendant
	// le gel, donc le multiplicateur du jeu se fige aussi — c'est voulu.
	paused: boolean;
```

Initialiser dans l'objet `state` de `launch` (après `velocity: 0,`) :

```ts
			paused: false,
```

Et sortir tôt de la boucle Heartbeat, tout en haut du callback :

```ts
		state.conn = RunService.Heartbeat.Connect((dt) => {
			if (state.paused) return; // vol gelé : on ne touche ni à la vélocité ni au pivot
			state.velocity = math.min(state.velocity + accel * dt, maxSpeed);
```

- [ ] **Step 3: Neutraliser la vélocité pendant le gel**

Remplacer `getVelocity` par :

```ts
	// Current ascent velocity (studs/s) for a room, or 0 if not flying / gelé. Read by
	// the game loop's multiplier tick so the payout multiplier tracks the rocket's speed
	// — un vol gelé ne fait donc pas grimper le multiplicateur.
	getVelocity(room: Room): number {
		const state = states.get(room);
		if (!state || state.paused) return 0;
		return state.velocity;
	},
```

- [ ] **Step 4: Ajouter `freeze` / `unfreeze` / `isFrozen`**

Insérer juste après `setSteer` :

```ts
	// Gèle le vol sur place : moteur éteint, roar en pause, plus aucun déplacement — la
	// vélocité acquise est gardée pour unfreeze. Utilisé par la mise en scène du tutorial
	// (aucun autre appelant). No-op si la room ne vole pas.
	freeze(room: Room): void {
		const state = states.get(room);
		if (!state || state.paused) return;
		state.paused = true;
		setNitroEnabled(room, false);
		const sound = launchSounds.get(room);
		if (sound) sound.Pause();
	},

	// Reprend un vol gelé à la vélocité qu'il avait.
	unfreeze(room: Room): void {
		const state = states.get(room);
		if (!state || !state.paused) return;
		state.paused = false;
		setNitroEnabled(room, true);
		const sound = launchSounds.get(room);
		if (sound) sound.Resume();
	},

	isFrozen(room: Room): boolean {
		return states.get(room)?.paused === true;
	},
```

- [ ] **Step 5: Compiler et relancer la sonde**

Run: `npm run build`
Expected: aucune sortie.

Relancer le jeu (`start_stop_play` pour redémarrer, afin que le serveur recharge le module compilé), puis rejouer la sonde Luau du Step 1.
Expected: `monte=true | gel_immobile=true | velocite_gelee_nulle=true | reprise=true`

- [ ] **Step 6: Commit**

```bash
git add src/server/modules/RocketLauncher.ts out/server/modules/RocketLauncher.luau
git commit -m "feat(rocket): freeze/unfreeze du vol (vélocité conservée, multiplicateur figé)"
```

---

## Task 4: Event, cheat et `TutorialService` (état + persistance)

**Files:**
- Modify: `src/shared/Event.ts`
- Modify: `src/server/modules/CheatConfig.ts`
- Create: `src/server/tutorial/TutorialService.ts`
- Modify: `src/server/services/index.ts`

**Interfaces:**
- Consumes: `TUTORIAL_STEPS`, `stepIndexById`, `stepById`, `firstStepId` (Task 1).
- Produces:
  - `Events.TutorialAdvanceEvent` (C→S, arg `stepId: string`, `"skip"` = terminer).
  - `TutorialService.init(): void`
  - `TutorialService.isActive(player): boolean`
  - `TutorialService.getCurrentStep(player): TutorialStep | undefined`
  - `TutorialService.advance(player, stepId: string): void` — n'avance que si `stepId` est le step courant.
  - `TutorialService.advanceTo(player, stepId: string): void` — avance jusqu'à ce step (traverse les intermédiaires).
  - `TutorialService.finish(player, skipped: boolean): void`
  - `TutorialService.devRestart(player): void` / `TutorialService.devGoto(player, stepId): void`
  - `forceTutorial: boolean` (CheatConfig).
- Note : les appels analytics sont ajoutés en Task 5 — ce fichier ne les contient pas encore.

- [ ] **Step 1: Déclarer le RemoteEvent**

Dans `src/shared/Event.ts`, avant la fermeture du namespace :

```ts
	// Tutorial — client → server. Arg: stepId (string). Le client signale que la
	// condition du step courant est remplie ; le serveur IGNORE l'event si l'id ne
	// correspond pas au step courant (anti double-avance / event en retard).
	// L'id spécial "skip" termine le tutorial (bouton TutorialSkip).
	export const TutorialAdvanceEvent = DefineEvent("TutorialAdvanceEvent", script);
```

- [ ] **Step 2: Ajouter le cheat**

À la fin de `src/server/modules/CheatConfig.ts` :

```ts
// ── Tutorial ──────────────────────────────────────────────────────────────────
// Force le tutorial à la connexion en IGNORANT la sauvegarde tuto (le joueur le
// refait même s'il l'a déjà terminé). À utiliser avec `resetData` pour re-tester
// l'onboarding complet. MUST be false before publishing.
export const forceTutorial = false;
```

- [ ] **Step 3: Écrire `TutorialService`**

`src/server/tutorial/TutorialService.ts` :

```ts
import { DataStoreService, HttpService, Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { TutorialStep } from "shared/tutorial/TutorialTypes";
import { TUTORIAL_STEPS, firstStepId, stepById, stepIndexById } from "shared/tutorial/TutorialSteps";
import { forceTutorial } from "server/modules/CheatConfig";

// État du tutorial par joueur. Le SERVEUR est la source de vérité de l'étape courante :
// il la publie via l'attribut répliqué `TutorialStep` (le client ne fait que lire et
// rendre), la persiste dans son propre store et l'avance sur signal client.
//
// Store dédié PlayerTutorial_v1 : aucune migration ni risque sur PlayerData/Progression,
// et retirer le tutorial ne laisse qu'un store orphelin inoffensif.

const STEP_ATTR = "TutorialStep";
const STORE_NAME = "PlayerTutorial_v1";
const SKIP_ID = "skip";

interface TutorialSave {
	step: string; // id du step courant ("" une fois terminé)
	done: boolean; // terminé (complété OU skippé) → module inerte à vie
	runId: string; // GUID de la tentative — garde le même funnel analytics après un relog
	elapsed: number; // secondes cumulées passées dans le tuto (hors temps hors-ligne)
}

interface TutorialState extends TutorialSave {
	stepEnteredAt: number; // os.time() de l'entrée dans le step courant
}

const dataStore = DataStoreService.GetDataStore(STORE_NAME);
const states = new Map<Player, TutorialState>();
// Seuls les joueurs dont le load a réussi sont sauvegardables — un échec transitoire
// ne doit jamais écraser une progression existante.
const loadedPlayers = new Set<Player>();

function keyFor(player: Player): string {
	return `Player_${player.UserId}`;
}

function newRunId(): string {
	const [ok, id] = pcall(() => HttpService.GenerateGUID(false));
	return ok ? (id as string) : `${tick()}`;
}

function freshSave(): TutorialSave {
	return { step: firstStepId(), done: false, runId: newRunId(), elapsed: 0 };
}

function loadSave(player: Player): TutorialSave | undefined {
	const [success, result] = pcall(() => dataStore.GetAsync(keyFor(player)));
	if (!success) {
		warn(`TutorialService: failed to load ${player.Name}: ${result}`);
		return undefined;
	}
	if (result === undefined || !typeIs(result, "table")) return freshSave();

	const loaded = result as Partial<TutorialSave>;
	const save = freshSave();
	if (typeIs(loaded.step, "string")) save.step = loaded.step;
	if (loaded.done === true) save.done = true;
	if (typeIs(loaded.runId, "string")) save.runId = loaded.runId;
	if (typeIs(loaded.elapsed, "number")) save.elapsed = math.max(0, loaded.elapsed);
	// Un id inconnu (step renommé/retiré) fait repartir au début plutôt que de bloquer.
	if (!save.done && stepIndexById(save.step) === undefined) save.step = firstStepId();
	return save;
}

function savePlayer(player: Player): void {
	if (!loadedPlayers.has(player)) return;
	const state = states.get(player);
	if (!state) return;

	const data: TutorialSave = {
		step: state.step,
		done: state.done,
		runId: state.runId,
		elapsed: state.elapsed,
	};
	const [success, err] = pcall(() => dataStore.SetAsync(keyFor(player), data));
	if (!success) warn(`TutorialService: failed to save ${player.Name}: ${err}`);
}

// Publie l'étape courante vers le client (attribut répliqué). "" = plus de tutorial.
function publish(player: Player, stepId: string): void {
	player.SetAttribute(STEP_ATTR, stepId);
}

// Referme le step courant : cumule son temps et renvoie sa durée en secondes.
function closeStep(state: TutorialState): number {
	const spent = math.max(0, os.time() - state.stepEnteredAt);
	state.elapsed += spent;
	state.stepEnteredAt = os.time();
	return spent;
}

function enterStep(player: Player, state: TutorialState, stepId: string): void {
	state.step = stepId;
	state.stepEnteredAt = os.time();
	publish(player, stepId);
}

function finishTutorial(player: Player, state: TutorialState): void {
	closeStep(state);
	state.done = true;
	state.step = "";
	publish(player, "");
	savePlayer(player);
}

// Avance d'exactement un step (ou termine si c'était le dernier).
function advanceOne(player: Player, state: TutorialState): void {
	const index = stepIndexById(state.step);
	if (index === undefined) {
		finishTutorial(player, state);
		return;
	}
	closeStep(state);

	const nextIndex = index + 1;
	if (nextIndex >= TUTORIAL_STEPS.size()) {
		finishTutorial(player, state);
		return;
	}
	enterStep(player, state, TUTORIAL_STEPS[nextIndex].id);
	savePlayer(player);
}

function setupPlayer(player: Player): void {
	const save = loadSave(player);
	if (save !== undefined) loadedPlayers.add(player);

	const resolved = save ?? freshSave();
	// forceTutorial ignore la sauvegarde : on repart du premier step.
	if (forceTutorial) {
		resolved.done = false;
		resolved.step = firstStepId();
		resolved.elapsed = 0;
		resolved.runId = newRunId();
	}

	if (resolved.done) {
		states.set(player, { ...resolved, step: "", stepEnteredAt: os.time() });
		publish(player, "");
		return;
	}

	const state: TutorialState = { ...resolved, stepEnteredAt: os.time() };
	states.set(player, state);
	publish(player, state.step);
}

export const TutorialService = {
	init(): void {
		Players.PlayerAdded.Connect((player) => task.spawn(() => setupPlayer(player)));
		for (const player of Players.GetPlayers()) task.spawn(() => setupPlayer(player));

		Events.TutorialAdvanceEvent.OnServerEvent.Connect((player, stepId) => {
			if (!typeIs(stepId, "string")) return;
			const state = states.get(player);
			if (!state || state.done) return;

			if (stepId === SKIP_ID) {
				TutorialService.finish(player, true);
				return;
			}
			TutorialService.advance(player, stepId);
		});

		Players.PlayerRemoving.Connect((player) => {
			const state = states.get(player);
			if (state && !state.done) closeStep(state);
			savePlayer(player);
			states.delete(player);
			loadedPlayers.delete(player);
		});

		game.BindToClose(() => {
			const players = Players.GetPlayers();
			if (players.size() === 0) return;
			let remaining = players.size();
			for (const player of players) {
				task.spawn(() => {
					savePlayer(player);
					remaining -= 1;
				});
			}
			while (remaining > 0) task.wait(0.1);
		});
	},

	isActive(player: Player): boolean {
		const state = states.get(player);
		return state !== undefined && !state.done;
	},

	getCurrentStep(player: Player): TutorialStep | undefined {
		const state = states.get(player);
		if (!state || state.done) return undefined;
		return stepById(state.step);
	},

	// Avance SEULEMENT si `stepId` est bien le step courant — un event client en retard
	// ou rejoué ne peut donc pas sauter une étape.
	advance(player: Player, stepId: string): void {
		const state = states.get(player);
		if (!state || state.done || state.step !== stepId) return;
		advanceOne(player, state);
	},

	// Avance jusqu'à `stepId` en traversant les steps intermédiaires un par un (chaque
	// step est donc bien entré/sorti, ce qui garde le funnel analytique complet).
	// Utilisé par la mise en scène du run truqué : le saut est déterministe, il ne dépend
	// pas du timing d'un signal client.
	advanceTo(player: Player, stepId: string): void {
		const state = states.get(player);
		if (!state || state.done) return;
		const target = stepIndexById(stepId);
		if (target === undefined) return;

		let guard = 0;
		while (!state.done && stepIndexById(state.step) !== undefined) {
			const current = stepIndexById(state.step) as number;
			if (current >= target) break;
			advanceOne(player, state);
			guard += 1;
			if (guard > TUTORIAL_STEPS.size()) break; // garde-fou anti-boucle
		}
	},

	finish(player: Player, _skipped: boolean): void {
		const state = states.get(player);
		if (!state || state.done) return;
		finishTutorial(player, state);
	},

	// ── Dev (barre de commande / execute_luau) ────────────────────────────────
	devRestart(player: Player): void {
		const state: TutorialState = { ...freshSave(), stepEnteredAt: os.time() };
		states.set(player, state);
		loadedPlayers.add(player);
		publish(player, state.step);
		savePlayer(player);
	},

	devGoto(player: Player, stepId: string): void {
		if (stepIndexById(stepId) === undefined) {
			warn(`TutorialService.devGoto: step inconnu "${stepId}"`);
			return;
		}
		const state = states.get(player) ?? { ...freshSave(), stepEnteredAt: os.time() };
		state.done = false;
		states.set(player, state);
		loadedPlayers.add(player);
		enterStep(player, state, stepId);
		savePlayer(player);
	},
};
```

- [ ] **Step 4: Brancher dans le boot serveur**

Dans `src/server/services/index.ts`, ajouter l'import :

```ts
import { TutorialService } from "server/tutorial/TutorialService";
```

et l'entrée dans le tableau `services`, **juste après `AnalyticsService`** (donc après PlayerProgression, avant RoomService) :

```ts
	// Tutorial (satellite) — publie l'étape courante via l'attribut TutorialStep.
	// Après PlayerProgression (mêmes attributs lus par les steps), avant RoomService :
	// le premier step cible le bouton dès l'assignation de la room.
	TutorialService,
```

- [ ] **Step 5: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 6: Vérifier en Studio (état + avance + persistance)**

Mettre `forceTutorial = true` **temporairement** dans `src/server/modules/CheatConfig.ts`, rebuild (`npm run build`), puis `start_stop_play` et `execute_luau` (`datamodel_type: "Server"`) :

```lua
local Players = game:GetService("Players")
local TS = game:GetService("ServerScriptService"):WaitForChild("TS")
local TutorialService = require(TS.tutorial.TutorialService).TutorialService
local player = Players:GetPlayers()[1]

local start = player:GetAttribute("TutorialStep")
TutorialService:advance(player, "mauvais-id")      -- doit être ignoré
local afterBadId = player:GetAttribute("TutorialStep")
TutorialService:advance(player, start)             -- doit avancer d'un step
local afterGood = player:GetAttribute("TutorialStep")
TutorialService:advanceTo(player, "buy-rocket-speed")
local afterJump = player:GetAttribute("TutorialStep")
TutorialService:devGoto(player, "claim")
local afterGoto = player:GetAttribute("TutorialStep")
TutorialService:finish(player, true)
local afterFinish = player:GetAttribute("TutorialStep")

return string.format(
	"start=%s | id_invalide_ignore=%s | avance=%s | saut=%s | goto=%s | fin=%s",
	start, tostring(afterBadId == start), afterGood, afterJump, afterGoto,
	afterFinish == "" and "vide(ok)" or afterFinish
)
```

Expected: `start=go-to-button | id_invalide_ignore=true | avance=press-start | saut=buy-rocket-speed | goto=claim | fin=vide(ok)`

Puis vérifier la reprise : remettre `forceTutorial = false`, rebuild, `start_stop_play` deux fois (arrêt puis relance) et lire l'attribut au join :

```lua
local Players = game:GetService("Players")
return tostring(Players:GetPlayers()[1]:GetAttribute("TutorialStep"))
```
Expected: `` (chaîne vide) — le `finish` précédent a bien été persisté, le tutorial ne redémarre pas.

Enfin, remettre le joueur en tuto pour les tâches suivantes :
```lua
local Players = game:GetService("Players")
local TS = game:GetService("ServerScriptService"):WaitForChild("TS")
require(TS.tutorial.TutorialService).TutorialService:devRestart(Players:GetPlayers()[1])
return tostring(Players:GetPlayers()[1]:GetAttribute("TutorialStep"))
```
Expected: `go-to-button`

- [ ] **Step 7: Vérifier que `forceTutorial` est bien à `false`**

Run: `grep -n "forceTutorial" src/server/modules/CheatConfig.ts`
Expected: la ligne `export const forceTutorial = false;`

- [ ] **Step 8: Commit**

```bash
git add src/shared/Event.ts src/server/modules/CheatConfig.ts src/server/tutorial src/server/services/index.ts out/shared/Event.luau out/server/modules/CheatConfig.luau out/server/tutorial out/server/services/index.luau
git commit -m "feat(tutorial): service d'état, persistance dédiée et cheat forceTutorial"
```

---

## Task 5: Analytics du tutorial

**Files:**
- Modify: `src/server/services/AnalyticsService.ts`
- Create: `src/server/tutorial/TutorialAnalytics.ts`
- Modify: `src/server/tutorial/TutorialService.ts`

**Interfaces:**
- Consumes: `TutorialService` internals (Task 4), `TUTORIAL_STEPS` (Task 1).
- Produces:
  - `AnalyticsService.funnelStep(player, funnelName: string, sessionId: string, step: number, stepName: string): void`
  - `TutorialAnalytics.started(player, resumed: boolean)`, `.stepEntered(player, runId, index, stepId)`, `.stepDone(player, stepId, seconds)`, `.completed(player, runId, totalSeconds)`, `.skipped(player, stepId, seconds)`

- [ ] **Step 1: Généraliser le funnel dans AnalyticsService**

Dans `src/server/services/AnalyticsService.ts`, ajouter au-dessus de `export const AnalyticsService` :

```ts
// Un pas de funnel, quel que soit le funnel. pcall : une analytics qui throttle ne doit
// jamais casser le gameplay.
function logFunnelStep(
	player: Player,
	funnelName: string,
	sessionId: string,
	step: number,
	stepName: string,
): void {
	pcall(() => RobloxAnalytics.LogFunnelStepEvent(player, funnelName, sessionId, step, stepName));
}
```

et remplacer `runStep` par :

```ts
	// Funnel générique (n'importe quel nom de funnel) — utilisé par le tutorial.
	funnelStep(player: Player, funnelName: string, sessionId: string, step: number, stepName: string): void {
		logFunnelStep(player, funnelName, sessionId, step, stepName);
	},

	runStep(player: Player, runId: string, step: number, stepName: string): void {
		logFunnelStep(player, "CoreRun", runId, step, stepName);
	},
```

- [ ] **Step 2: Écrire `TutorialAnalytics`**

`src/server/tutorial/TutorialAnalytics.ts` :

```ts
import { AnalyticsService } from "server/services/AnalyticsService";
import { TUTORIAL_STEPS } from "shared/tutorial/TutorialSteps";

// Toute la sémantique analytics du tutorial (le jeu de base ne gagne qu'un helper
// générique, AnalyticsService.funnelStep). Voir le spec tutorial §9.
//
//   Funnel "Tutorial" : un pas à l'ENTRÉE de chaque step → le drop-off entre N et N+1
//   est le taux d'abandon PENDANT le step N. funnelSessionId = le runId persisté, donc
//   un joueur qui revient après un relog reste dans le même funnel.

const FUNNEL = "Tutorial";

export const TutorialAnalytics = {
	// Dénominateur : combien de joueurs commencent (ou reprennent) le tutorial.
	started(player: Player, resumed: boolean): void {
		AnalyticsService.custom(player, "TutorialStarted", 1, resumed ? "Resumed" : "Fresh");
	},

	// Entrée dans un step (index 0-based → pas de funnel 1-based).
	stepEntered(player: Player, runId: string, index: number, stepId: string): void {
		AnalyticsService.funnelStep(player, FUNNEL, runId, index + 1, stepId);
	},

	// Sortie d'un step, avec le temps passé dessus : repère les steps qui bloquent.
	stepDone(player: Player, stepId: string, seconds: number): void {
		AnalyticsService.custom(player, "TutorialStepDone", seconds, stepId);
	},

	// Tutorial terminé SANS skip : dernière marche du funnel + durée totale.
	completed(player: Player, runId: string, totalSeconds: number): void {
		AnalyticsService.funnelStep(player, FUNNEL, runId, TUTORIAL_STEPS.size() + 1, "Done");
		AnalyticsService.custom(player, "TutorialCompleted", totalSeconds, "NoSkip");
	},

	// Skip : la valeur est le temps écoulé, le breakdown le step d'où il est sorti.
	skipped(player: Player, stepId: string, seconds: number): void {
		AnalyticsService.custom(player, "TutorialSkipped", seconds, stepId);
	},
};
```

- [ ] **Step 3: Instrumenter `TutorialService`**

Dans `src/server/tutorial/TutorialService.ts`, ajouter l'import :

```ts
import { TutorialAnalytics } from "./TutorialAnalytics";
```

Remplacer `enterStep` par :

```ts
function enterStep(player: Player, state: TutorialState, stepId: string): void {
	state.step = stepId;
	state.stepEnteredAt = os.time();
	publish(player, stepId);
	const index = stepIndexById(stepId);
	if (index !== undefined) TutorialAnalytics.stepEntered(player, state.runId, index, stepId);
}
```

Remplacer `finishTutorial` par :

```ts
// `skipped` distingue les deux fins : un tutorial complété ne logge JAMAIS
// TutorialSkipped, et inversement.
function finishTutorial(player: Player, state: TutorialState, skipped: boolean): void {
	const lastStep = state.step;
	const spent = closeStep(state);
	if (skipped) TutorialAnalytics.skipped(player, lastStep, state.elapsed);
	else {
		TutorialAnalytics.stepDone(player, lastStep, spent);
		TutorialAnalytics.completed(player, state.runId, state.elapsed);
	}
	state.done = true;
	state.step = "";
	publish(player, "");
	savePlayer(player);
}
```

Dans `advanceOne`, logger la durée du step quitté et propager `skipped: false` :

```ts
function advanceOne(player: Player, state: TutorialState): void {
	const index = stepIndexById(state.step);
	if (index === undefined) {
		finishTutorial(player, state, false);
		return;
	}
	const leaving = state.step;
	const spent = closeStep(state);
	TutorialAnalytics.stepDone(player, leaving, spent);

	const nextIndex = index + 1;
	if (nextIndex >= TUTORIAL_STEPS.size()) {
		finishTutorial(player, state, false);
		return;
	}
	enterStep(player, state, TUTORIAL_STEPS[nextIndex].id);
	savePlayer(player);
}
```

Dans `setupPlayer`, après `publish(player, state.step);` :

```ts
	// "Resumed" = le joueur reprend un tutorial commencé dans une session précédente.
	const resumed = state.step !== firstStepId() || state.elapsed > 0;
	TutorialAnalytics.started(player, resumed);
	const index = stepIndexById(state.step);
	if (index !== undefined) TutorialAnalytics.stepEntered(player, state.runId, index, state.step);
```

Enfin, brancher le flag dans `finish` et `devRestart` :

```ts
	finish(player: Player, skipped: boolean): void {
		const state = states.get(player);
		if (!state || state.done) return;
		finishTutorial(player, state, skipped);
	},
```

(et dans `devRestart`, remplacer `publish(player, state.step);` par `enterStep(player, state, state.step);` pour que le funnel reparte proprement).

- [ ] **Step 4: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 5: Vérifier que les 4 compteurs partent**

`start_stop_play`, puis `execute_luau` (`datamodel_type: "Server"`). Les appels analytics étant silencieux (pcall vers l'API Roblox, invisible en Play Solo), on vérifie par instrumentation temporaire : hooker l'API et compter les appels.

```lua
local Players = game:GetService("Players")
local TS = game:GetService("ServerScriptService"):WaitForChild("TS")
local Analytics = require(TS.services.AnalyticsService).AnalyticsService
local TutorialService = require(TS.tutorial.TutorialService).TutorialService
local player = Players:GetPlayers()[1]

local seen = {}
local realCustom, realFunnel = Analytics.custom, Analytics.funnelStep
Analytics.custom = function(self, p, name, value, field)
	table.insert(seen, string.format("%s(%s,%s)", name, tostring(value), tostring(field)))
	return realCustom(self, p, name, value, field)
end
Analytics.funnelStep = function(self, p, funnel, session, step, stepName)
	table.insert(seen, string.format("funnel:%s#%d=%s", funnel, step, stepName))
	return realFunnel(self, p, funnel, session, step, stepName)
end

TutorialService:devRestart(player)
TutorialService:advance(player, "go-to-button")
task.wait(1)
TutorialService:advance(player, "press-start")
TutorialService:finish(player, true)

Analytics.custom, Analytics.funnelStep = realCustom, realFunnel
return table.concat(seen, "\n")
```

Expected: une liste contenant `TutorialStarted(1,Fresh)`, plusieurs `funnel:Tutorial#N=<stepId>`, des `TutorialStepDone(<secondes>,<stepId>)`, et **`TutorialSkipped`** — mais **aucun `TutorialCompleted`** (c'était un skip).

- [ ] **Step 6: Commit**

```bash
git add src/server/services/AnalyticsService.ts src/server/tutorial out/server/services/AnalyticsService.luau out/server/tutorial
git commit -m "feat(tutorial): analytics (funnel Tutorial + 4 compteurs)"
```

---

## Task 6: Run truqué — `TutorialRunDirector` + hooks

**Files:**
- Create: `src/server/tutorial/TutorialRunDirector.ts`
- Create: `src/server/tutorial/TutorialHooks.ts`
- Modify: `src/server/modules/ButtonInGameModule.ts`
- Modify: `src/server/tutorial/TutorialService.ts` (abort du run à la fin du tuto)

**Interfaces:**
- Consumes: `RocketLauncher.freeze/unfreeze` (Task 3), `TutorialService.getCurrentStep/advanceTo/isActive` (Task 4), `Room`, `ButtonSessionService.getSession`.
- Produces:
  - `interface ScriptedRunHandle { explosionAt(): number; onClaim(): void }`
  - `TutorialRunDirector.begin(player, room, run: ScriptedRun): ScriptedRunHandle`
  - `TutorialRunDirector.abort(player): void`
  - `TutorialHooks.beginRun(player, room): ScriptedRunHandle | undefined`

- [ ] **Step 1: Écrire le director**

`src/server/tutorial/TutorialRunDirector.ts` :

```ts
import { Room } from "server/rooms/Room";
import { RocketLauncher } from "server/modules/RocketLauncher";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { ScriptedRun } from "shared/tutorial/TutorialTypes";
import { TutorialService } from "./TutorialService";

// Met en scène le run truqué du tutorial. Le jeu de base ne connaît que le handle
// ci-dessous : il lui demande la deadline d'explosion à chaque tick et le prévient du
// claim. Tout le scénario (quand geler, quand relancer, quel délai) vit ici.
//
// La deadline est RÉÉCRITE au claim (explodeAfterClaim) : c'est pourquoi le jeu doit la
// relire à chaque tour de boucle plutôt que de la lire une fois au décollage.

// Si le tutorial est coupé (skip) pendant un run truqué sans risque, la fusée volerait
// pour toujours. On résout alors le run en le faisant exploser peu après.
const ABORT_EXPLODE_DELAY = 2;

export interface ScriptedRunHandle {
	// Secondes de vol au bout desquelles la fusée doit exploser (math.huge = jamais).
	explosionAt(): number;
	// Le joueur vient de claim.
	onClaim(): void;
}

const activeHandles = new Map<Player, { abort: () => void }>();

export const TutorialRunDirector = {
	begin(player: Player, room: Room, run: ScriptedRun): ScriptedRunHandle {
		const startedAt = os.clock();
		// noRisk (ou rien de précisé) → aucune explosion tant que le script n'en programme
		// pas une. explodeAt fixe l'instant depuis le décollage.
		let deadline = run.explodeAt ?? math.huge;
		let frozen = false;

		const elapsed = (): number => os.clock() - startedAt;
		// Le run n'est plus le nôtre si la session a été nettoyée ou a changé de room.
		const stillRunning = (): boolean => ButtonSessionService.getSession(player)?.room === room;

		if (run.freezeAt !== undefined) {
			task.delay(run.freezeAt, () => {
				if (!stillRunning()) return;
				RocketLauncher.freeze(room);
				frozen = true;
				// Saut d'étape DÉTERMINISTE : on ne dépend pas du timing d'un signal client.
				if (run.advanceToOnFreeze !== undefined) {
					TutorialService.advanceTo(player, run.advanceToOnFreeze);
				}
			});
		}

		activeHandles.set(player, {
			abort: () => {
				if (frozen) {
					RocketLauncher.unfreeze(room);
					frozen = false;
				}
				// Le run doit se terminer tout seul, sinon la fusée reste en l'air.
				if (deadline === math.huge) deadline = elapsed() + ABORT_EXPLODE_DELAY;
			},
		});

		return {
			explosionAt: () => deadline,
			onClaim: () => {
				if (run.unfreezeOnClaim === true && frozen) {
					RocketLauncher.unfreeze(room);
					frozen = false;
				}
				if (run.explodeAfterClaim !== undefined) {
					deadline = elapsed() + run.explodeAfterClaim;
				}
			},
		};
	},

	// Appelé quand le tutorial se termine (skip) : un run scripté en cours doit pouvoir
	// se conclure normalement.
	abort(player: Player): void {
		activeHandles.get(player)?.abort();
		activeHandles.delete(player);
	},
};
```

- [ ] **Step 2: Écrire le hook**

`src/server/tutorial/TutorialHooks.ts` :

```ts
import { Room } from "server/rooms/Room";
import { ScriptedRunHandle, TutorialRunDirector } from "./TutorialRunDirector";
import { TutorialService } from "./TutorialService";

// LA seule API que le jeu de base appelle. Hors tutorial (ou sur un step sans scénario)
// tout renvoie undefined : le jeu garde exactement son comportement normal.
export const TutorialHooks = {
	// Démarre la mise en scène du run si le step courant en porte une.
	beginRun(player: Player, room: Room): ScriptedRunHandle | undefined {
		const step = TutorialService.getCurrentStep(player);
		if (!step || step.run === undefined) return undefined;
		return TutorialRunDirector.begin(player, room, step.run);
	},
};
```

- [ ] **Step 3: Brancher les 3 lignes dans `ButtonInGameModule`**

Dans `src/server/modules/ButtonInGameModule.ts`, ajouter l'import :

```ts
import { TutorialHooks } from "server/tutorial/TutorialHooks";
```

Dans `startButtonGame`, juste avant `const explosionAt = ...` :

```ts
	// Tutorial : si le step courant impose un scénario (gel, explosion programmée), le
	// director le joue et fournit la deadline d'explosion — qu'il peut réécrire au claim.
	// undefined hors tutorial → comportement normal intégral.
	const scripted = TutorialHooks.beginRun(player, room);
```

Dans le handler de claim, après la ligne `Events.ClaimAcceptedEvent.FireClient(player, claimedMultiplier);` :

```ts
		scripted?.onClaim(); // tutorial : relance la fusée gelée + programme l'explosion
```

Dans la boucle risque, remplacer les deux usages de `explosionAt` par une deadline relue à chaque tour. Le bloc devient :

```ts
		while (isActive) {
			// La deadline est relue à CHAQUE tour : le tutorial la réécrit au claim.
			const deadline = scripted !== undefined ? scripted.explosionAt() : explosionAt;
			// Avance jusqu'au prochain pas sans jamais dépasser l'instant d'explosion
			// précalculé → l'explosion tombe pile à l'heure.
			const nextStep = math.min(timeHeld + TICK_RATE, deadline);
			task.wait(nextStep - timeHeld);
			if (!isActive) break;

			timeHeld = nextStep;

			if (!invincible && timeHeld >= deadline) {
```

- [ ] **Step 4: Résoudre le run scripté quand le tutorial s'arrête — via callback, PAS d'import**

`TutorialService` ne doit **pas** importer `TutorialRunDirector` : le director importe déjà le service, et un cycle de `require` casse à l'exécution en Luau. On utilise le même patron que `UiService.SetBeforeShow` dans ce projet : un callback enregistré, pour que le service reste libre de toute dépendance de mise en scène.

Dans `src/server/tutorial/TutorialService.ts`, ajouter près des autres états de module :

```ts
// Appelé quand le tutorial se termine, pour qu'un run truqué encore en vol puisse se
// conclure (sinon une fusée sans risque volerait indéfiniment). Enregistré par
// TutorialRunDirector — un callback plutôt qu'un import, pour éviter un cycle de require.
let runAbortHandler: ((player: Player) => void) | undefined;
```

Dans `finishTutorial`, juste avant `savePlayer(player);` :

```ts
	if (runAbortHandler !== undefined) runAbortHandler(player);
```

Et exposer le setter dans l'objet `TutorialService` (à côté de `finish`) :

```ts
	// Enregistre le handler d'annulation de run truqué (voir runAbortHandler).
	setRunAbortHandler(handler: (player: Player) => void): void {
		runAbortHandler = handler;
	},
```

Enfin, à la fin de `src/server/tutorial/TutorialRunDirector.ts`, après l'objet exporté :

```ts
// Le service annonce la fin du tutorial ; le director résout le run en vol. Enregistré à
// la première charge du module (ButtonInGameModule → TutorialHooks → ici).
TutorialService.setRunAbortHandler((player) => TutorialRunDirector.abort(player));
```

- [ ] **Step 5: Compiler**

Run: `npm run build`
Expected: aucune sortie. Vérifier ensuite qu'aucun cycle n'a été réintroduit :

Run: `grep -n "TutorialRunDirector" src/server/tutorial/TutorialService.ts`
Expected: **aucune ligne** — le service ne connaît que son callback.

- [ ] **Step 6: Vérifier le scénario complet en Studio**

`start_stop_play`, puis `execute_luau` (`datamodel_type: "Server"`) — on simule le run guidé de bout en bout et on mesure :

```lua
local Players = game:GetService("Players")
local TS = game:GetService("ServerScriptService"):WaitForChild("TS")
local RoomService = require(TS.rooms.RoomService).RoomService
local RocketLauncher = require(TS.modules.RocketLauncher).RocketLauncher
local TutorialService = require(TS.tutorial.TutorialService).TutorialService
local TutorialHooks = require(TS.tutorial.TutorialHooks).TutorialHooks
local ButtonSessionService = require(TS.services.ButtonSessionService).ButtonSessionService

local player = Players:GetPlayers()[1]
local room = RoomService:getRoom(player)
TutorialService:devGoto(player, "press-start")
ButtonSessionService:setSession(player, { room = room })

local handle = TutorialHooks:beginRun(player, room)
assert(handle, "beginRun a renvoyé nil sur le step press-start")
RocketLauncher:launch(room, 1)

local before = handle:explosionAt()             -- doit être math.huge (noRisk)
task.wait(3)                                    -- le gel tombe à 2.5 s
local frozen = RocketLauncher:isFrozen(room)
local stepAtFreeze = player:GetAttribute("TutorialStep")

handle:onClaim()
local afterClaim = handle:explosionAt()          -- ≈ 3 + 1 s
local unfrozen = not RocketLauncher:isFrozen(room)

RocketLauncher:reset(room)
ButtonSessionService:cleanup(player)
return string.format(
	"deadline_initiale_infinie=%s | gele_a_2.5s=%s | step=%s | relance_au_claim=%s | deadline_apres_claim=%.2f",
	tostring(before == math.huge), tostring(frozen), tostring(stepAtFreeze),
	tostring(unfrozen), afterClaim
)
```

Expected: `deadline_initiale_infinie=true | gele_a_2.5s=true | step=claim | relance_au_claim=true | deadline_apres_claim=4.0x` (valeur entre 3,9 et 4,2).

- [ ] **Step 7: Commit**

```bash
git add src/server/tutorial src/server/modules/ButtonInGameModule.ts out/server/tutorial out/server/modules/ButtonInGameModule.luau
git commit -m "feat(tutorial): mise en scène du run truqué (gel 2,5s, explosion 1s après le claim)"
```

---

## Task 7: Client — bandeau, bouton Skip et contrôleur

**Files:**
- Create: `src/client/tutorial/TutorialUI.ts`
- Create: `src/client/tutorial/TutorialSkipButton.ts`
- Create: `src/client/tutorial/TutorialController.ts`
- Modify: `src/client/main.client.ts`

**Interfaces:**
- Consumes: `TUTORIAL_STEPS`/`stepById` (Task 1), `Events.TutorialAdvanceEvent` (Task 4).
- Produces:
  - `TutorialUI.ensure(): ScreenGui`, `TutorialUI.setText(text: string): void`, `TutorialUI.hideBanner(): void`, `TutorialUI.destroy(): void`, `TutorialUI.getInGameUI(): ScreenGui | undefined`
  - `TutorialSkipButton.init(onSkip: () => void): void`, `TutorialSkipButton.setVisible(visible: boolean): void`
  - `init(): void` (TutorialController) — exporté sous le nom `initTutorial` dans `main.client.ts`.

- [ ] **Step 1: Écrire `TutorialUI`**

`src/client/tutorial/TutorialUI.ts` :

```ts
import { Players } from "@rbxts/services";

// Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
// bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
// le bandeau d'instruction. Détruit intégralement à la fin du tutorial.

const GUI_NAME = "TutorialUI";
const IN_GAME_UI = "InGameUI";
// Au-dessus de InGameUI (qui n'a pas de DisplayOrder explicite, donc 0).
const DISPLAY_ORDER = 100;

let screenGui: ScreenGui | undefined;
let banner: Frame | undefined;
let label: TextLabel | undefined;

function playerGui(): PlayerGui {
	return Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
}

export const TutorialUI = {
	// Le ScreenGui du jeu — sert de référence de coordonnées (même GuiInset) et de
	// racine pour résoudre les cibles GUI.
	getInGameUI(): ScreenGui | undefined {
		const found = playerGui().FindFirstChild(IN_GAME_UI);
		return found?.IsA("ScreenGui") ? found : undefined;
	},

	ensure(): ScreenGui {
		if (screenGui && screenGui.Parent !== undefined) return screenGui;

		const gui = new Instance("ScreenGui");
		gui.Name = GUI_NAME;
		gui.ResetOnSpawn = false;
		gui.DisplayOrder = DISPLAY_ORDER;
		// Aligner l'inset sur celui du GUI du jeu, sinon tous les rectangles de cible
		// seraient décalés de la hauteur de la barre Roblox.
		gui.IgnoreGuiInset = TutorialUI.getInGameUI()?.IgnoreGuiInset ?? false;
		gui.Parent = playerGui();
		screenGui = gui;

		const frame = new Instance("Frame");
		frame.Name = "InstructionBanner";
		frame.AnchorPoint = new Vector2(0.5, 1);
		frame.Position = new UDim2(0.5, 0, 1, -24);
		frame.Size = new UDim2(0.9, 0, 0, 64);
		frame.BackgroundColor3 = Color3.fromRGB(12, 12, 20);
		frame.BackgroundTransparency = 0.25;
		frame.BorderSizePixel = 0;
		frame.Visible = false;
		frame.Parent = gui;
		banner = frame;

		const corner = new Instance("UICorner");
		corner.CornerRadius = new UDim(0, 12);
		corner.Parent = frame;

		const stroke = new Instance("UIStroke");
		stroke.Thickness = 2;
		stroke.Color = Color3.fromRGB(255, 255, 255);
		stroke.Transparency = 0.5;
		stroke.Parent = frame;

		const text = new Instance("TextLabel");
		text.Name = "InstructionText";
		text.BackgroundTransparency = 1;
		text.Size = new UDim2(1, -24, 1, -12);
		text.Position = new UDim2(0, 12, 0, 6);
		text.Font = Enum.Font.GothamBold;
		text.TextScaled = true;
		text.TextColor3 = new Color3(1, 1, 1);
		text.TextWrapped = true;
		text.Text = "";
		text.Parent = frame;
		label = text;

		const textSize = new Instance("UITextSizeConstraint");
		textSize.MaxTextSize = 22;
		textSize.Parent = text;

		return gui;
	},

	setText(value: string): void {
		TutorialUI.ensure();
		if (!banner || !label) return;
		label.Text = value;
		banner.Visible = value !== "";
	},

	hideBanner(): void {
		if (banner) banner.Visible = false;
	},

	destroy(): void {
		if (screenGui) screenGui.Destroy();
		screenGui = undefined;
		banner = undefined;
		label = undefined;
	},
};
```

- [ ] **Step 2: Écrire `TutorialSkipButton`**

`src/client/tutorial/TutorialSkipButton.ts` :

```ts
import { Players } from "@rbxts/services";

// Le bouton Skip est AUTHORÉ DANS STUDIO (visuel maison) — le code ne fait que
// l'allumer/l'éteindre et écouter son clic. Hiérarchie attendue :
//   InGameUI/TutorialSkip (Frame)  ← visibilité pilotée ici
//     └── TutorialSkipFrame/TextButton
// Résolu par NOM en recherche récursive, pour que le frame puisse être déplacé dans
// Studio sans toucher au code. TutorialSkip est un frère du HUD (et non un enfant) :
// il survit donc au masquage du HUD pendant un run.

const ROOT_NAME = "TutorialSkip";
const BUTTON_NAME = "TextButton";

let root: Frame | undefined;
let connected = false;

function findRoot(): Frame | undefined {
	if (root && root.Parent !== undefined) return root;
	const gui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
	const found = gui.FindFirstChild(ROOT_NAME, true);
	root = found?.IsA("Frame") ? found : undefined;
	if (!root) warn(`TutorialSkipButton: ${ROOT_NAME} introuvable sous PlayerGui`);
	return root;
}

export const TutorialSkipButton = {
	init(onSkip: () => void): void {
		const frame = findRoot();
		if (!frame || connected) return;

		const button = frame.FindFirstChild(BUTTON_NAME, true);
		if (!button?.IsA("GuiButton")) {
			warn(`TutorialSkipButton: aucun ${BUTTON_NAME} sous ${ROOT_NAME}`);
			return;
		}
		button.Activated.Connect(() => onSkip());
		connected = true;
	},

	setVisible(visible: boolean): void {
		const frame = findRoot();
		if (frame) frame.Visible = visible;
	},
};
```

- [ ] **Step 3: Écrire le contrôleur (bandeau + skip uniquement)**

`src/client/tutorial/TutorialController.ts` :

```ts
import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { TutorialStep } from "shared/tutorial/TutorialTypes";
import { stepById } from "shared/tutorial/TutorialSteps";
import { TutorialUI } from "./TutorialUI";
import { TutorialSkipButton } from "./TutorialSkipButton";

// Orchestre le rendu du tutorial côté client. Le serveur publie l'étape courante dans
// l'attribut répliqué TutorialStep ("" = terminé) ; ce contrôleur la lit, monte la mise
// en scène du step, et remonte la complétion via TutorialAdvanceEvent.

const STEP_ATTR = "TutorialStep";
const SKIP_ID = "skip";

const player = Players.LocalPlayer;

// Démontage de la mise en scène du step courant.
let teardown: (() => void) | undefined;

function clearStep(): void {
	if (teardown) {
		teardown();
		teardown = undefined;
	}
	TutorialUI.hideBanner();
}

function showStep(step: TutorialStep): void {
	clearStep();
	TutorialUI.ensure();
	TutorialUI.setText(step.text);
}

function render(): void {
	const stepId = (player.GetAttribute(STEP_ATTR) as string | undefined) ?? "";
	if (stepId === "") {
		// Tutorial terminé : on démonte tout, plus une seule connexion active.
		clearStep();
		TutorialSkipButton.setVisible(false);
		TutorialUI.destroy();
		return;
	}

	const step = stepById(stepId);
	if (!step) {
		warn(`TutorialController: step inconnu "${stepId}"`);
		return;
	}
	TutorialSkipButton.setVisible(true);
	showStep(step);
}

export function init(): void {
	TutorialSkipButton.init(() => Events.TutorialAdvanceEvent.FireServer(SKIP_ID));
	// Masqué par défaut : un joueur qui a déjà fini ne doit jamais le voir.
	TutorialSkipButton.setVisible(false);

	player.GetAttributeChangedSignal(STEP_ATTR).Connect(render);
	// L'attribut peut déjà être arrivé avant l'init du client.
	render();
}
```

- [ ] **Step 4: Brancher dans `main.client.ts`**

Ajouter l'import (à la suite des autres) :

```ts
import { init as initTutorial } from "./tutorial/TutorialController";
```

et l'appel, **en dernier** de la liste d'inits :

```ts
initTutorial();
```

- [ ] **Step 5: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 6: Vérifier à l'écran**

Passer `forceTutorial = true`, `npm run build`, `start_stop_play`.

Attendu visuellement (MCP `screen_capture` pour confirmer) : le bandeau « Va appuyer sur ton bouton ! » en bas de l'écran, et le bouton `TutorialSkip` visible.

Puis, en `execute_luau` (`datamodel_type: "Client"`) :

```lua
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local tut = gui:FindFirstChild("TutorialUI")
local banner = tut and tut:FindFirstChild("InstructionBanner")
local label = banner and banner:FindFirstChild("InstructionText")
local skip = gui:FindFirstChild("TutorialSkip", true)
return string.format(
	"gui=%s | bandeau_visible=%s | texte=%s | skip_visible=%s | ordre=%s",
	tostring(tut ~= nil), tostring(banner and banner.Visible),
	tostring(label and label.Text), tostring(skip and skip.Visible),
	tostring(tut and tut.DisplayOrder)
)
```
Expected: `gui=true | bandeau_visible=true | texte=Va appuyer sur ton bouton ! | skip_visible=true | ordre=100`

Vérifier ensuite le Skip : cliquer le bouton en jeu (ou `execute_luau` client sur son `Activated`), puis relire.
Expected: `gui=false | ... | skip_visible=false` — l'UI tuto est détruite et le Skip masqué.

- [ ] **Step 7: Remettre le cheat à false et committer**

```bash
grep -n "forceTutorial = false" src/server/modules/CheatConfig.ts
git add src/client/tutorial src/client/main.client.ts out/client/tutorial out/client/main.client.luau
git commit -m "feat(tutorial): UI client (bandeau d'instruction) et bouton Skip"
```

---

## Task 8: Client — résolution des cibles et détection des complétions

**Files:**
- Create: `src/client/tutorial/TutorialTargets.ts`
- Create: `src/client/tutorial/TutorialTriggers.ts`
- Modify: `src/client/tutorial/TutorialController.ts`

**Interfaces:**
- Consumes: `TutorialUI.getInGameUI` (Task 7), types (Task 1).
- Produces:
  - `TutorialTargets.resolveGui(path: string): GuiObject | undefined`
  - `TutorialTargets.resolveWorld(id: WorldTargetId): BasePart | undefined`
  - `TutorialTriggers.watch(step: TutorialStep, onComplete: () => void): () => void` — retourne le démontage.

- [ ] **Step 1: Écrire la résolution des cibles**

`src/client/tutorial/TutorialTargets.ts` :

```ts
import { Players, Workspace } from "@rbxts/services";
import { WorldTargetId } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Résout une cible de step en instance concrète.
//   "gui"   → chemin slash-séparé sous InGameUI, ex "ButtonMenu/StartButton"
//   "world" → une part du monde. StreamingEnabled est ACTIF : la découverte passe par
//             WaitForChild plutôt qu'un FindFirstChild one-shot (voir RoomPromptController).

const PLAYER_ZONES = "PlayerZones";
const BUTTON_MODEL = "ButtonModel";
const BUTTON_PART = "ButtonPart";
const SHOP = "Shop";
const SHOP_PROMPT_PART = "ProximityPromptPart";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";

export const TutorialTargets = {
	resolveGui(path: string): GuiObject | undefined {
		const root = TutorialUI.getInGameUI();
		if (!root) return undefined;

		let node: Instance | undefined = root;
		for (const part of path.split("/")) {
			node = node?.FindFirstChild(part);
			if (!node) return undefined;
		}
		return node.IsA("GuiObject") ? node : undefined;
	},

	// Peut yielder (WaitForChild) — appeler depuis un task.spawn.
	resolveWorld(id: WorldTargetId): BasePart | undefined {
		if (id === "Shop") {
			const shop = Workspace.WaitForChild(SHOP, 10);
			const part = shop?.WaitForChild(SHOP_PROMPT_PART, 10);
			return part?.IsA("BasePart") ? part : undefined;
		}

		// RoomButton — le bouton de la room ASSIGNÉE au joueur local.
		const roomName = (Players.LocalPlayer.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		if (roomName === "") return undefined;

		const zones = Workspace.WaitForChild(PLAYER_ZONES, 10);
		const room = zones?.WaitForChild(roomName, 10);
		const model = room?.WaitForChild(BUTTON_MODEL, 10);
		const part = model?.WaitForChild(BUTTON_PART, 10);
		return part?.IsA("BasePart") ? part : undefined;
	},
};
```

- [ ] **Step 2: Écrire la détection des complétions**

`src/client/tutorial/TutorialTriggers.ts` :

```ts
import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { PopupOrMenuName, TutorialStep } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Surveille la condition de complétion d'un step et appelle onComplete UNE fois.
// Tout est détecté avec ce que le client voit déjà : events serveur → client existants,
// attributs répliqués, et visibilité des frames de InGameUI. Aucun nouvel event.
//
// Le trigger "server" ne branche RIEN : c'est le serveur qui sort du step (run truqué).

const player = Players.LocalPlayer;

function findPopup(name: PopupOrMenuName): GuiObject | undefined {
	const root = TutorialUI.getInGameUI();
	const found = root?.FindFirstChild(name);
	return found?.IsA("GuiObject") ? found : undefined;
}

export const TutorialTriggers = {
	// Retourne la fonction de démontage (à appeler au changement de step).
	watch(step: TutorialStep, onComplete: () => void): () => void {
		const trigger = step.complete;
		let done = false;
		const fire = (): void => {
			if (done) return;
			done = true;
			onComplete();
		};

		if (trigger.kind === "server") {
			return () => {};
		}

		if (trigger.kind === "event") {
			const conn =
				trigger.event === "ButtonTrigger"
					? Events.ButtonTriggerEvent.OnClientEvent.Connect(() => fire())
					: Events.ClaimAcceptedEvent.OnClientEvent.Connect(() => fire());
			return () => conn.Disconnect();
		}

		if (trigger.kind === "attribute") {
			// Seuil RELATIF : un joueur existant a déjà des niveaux, on attend une hausse
			// depuis l'entrée dans le step.
			const baseline = (player.GetAttribute(trigger.attribute) as number | undefined) ?? 0;
			const conn = player.GetAttributeChangedSignal(trigger.attribute).Connect(() => {
				const current = (player.GetAttribute(trigger.attribute) as number | undefined) ?? 0;
				if (current >= baseline + trigger.increaseBy) fire();
			});
			return () => conn.Disconnect();
		}

		// popup / popupClosed — la frame de InGameUI devient visible / invisible.
		const wantVisible = trigger.kind === "popup";
		const frame = findPopup(trigger.popup);
		if (!frame) {
			warn(`TutorialTriggers: frame "${trigger.popup}" introuvable sous InGameUI`);
			return () => {};
		}
		// popupClosed n'est valide qu'après une ouverture : sinon un step attendant la
		// fermeture d'une popup déjà fermée passerait instantanément.
		let seenOpen = frame.Visible;
		const conn = frame.GetPropertyChangedSignal("Visible").Connect(() => {
			if (frame.Visible) {
				seenOpen = true;
				if (wantVisible) fire();
				return;
			}
			if (!wantVisible && seenOpen) fire();
		});
		if (wantVisible && frame.Visible) fire();
		return () => conn.Disconnect();
	},
};
```

- [ ] **Step 3: Brancher dans le contrôleur**

Dans `src/client/tutorial/TutorialController.ts`, ajouter l'import :

```ts
import { TutorialTriggers } from "./TutorialTriggers";
```

et remplacer `showStep` par :

```ts
function showStep(step: TutorialStep): void {
	clearStep();
	TutorialUI.ensure();
	TutorialUI.setText(step.text);

	// La complétion est remontée au serveur, qui valide que c'est bien le step courant.
	const stopWatching = TutorialTriggers.watch(step, () => {
		Events.TutorialAdvanceEvent.FireServer(step.id);
	});
	teardown = () => stopWatching();
}
```

- [ ] **Step 4: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 5: Vérifier le déroulé complet, texte seulement**

`forceTutorial = true`, `npm run build`, `start_stop_play`, puis **jouer réellement** le tutorial à la souris/clavier dans la fenêtre Studio : aller au bouton, START, attendre le gel, CLAIM, laisser le payout, aller à la boutique, acheter Rocket Speed, revenir au bouton.

Après chaque étape, lire l'étape courante :
```lua
return tostring(game:GetService("Players"):GetPlayers()[1]:GetAttribute("TutorialStep"))
```

Expected, dans l'ordre : `go-to-button` → `press-start` → (au gel) `claim` → `claim-explode` → `go-to-shop` → `buy-rocket-speed` → `back-to-button` → `` (vide, tutorial terminé).

Points à contrôler pendant le run : la fusée se gèle bien vers 2,5 s, le multiplicateur se fige, le claim la relance et l'explosion tombe ~1 s après, l'argent est bien crédité, et la boutique affiche **25 $** puis **50 $** sur `ARocketSpeed`.

- [ ] **Step 6: Remettre le cheat à false et committer**

```bash
grep -n "forceTutorial = false" src/server/modules/CheatConfig.ts
git add src/client/tutorial out/client/tutorial
git commit -m "feat(tutorial): résolution des cibles et détection des complétions"
```

---

## Task 9: Client — flèches (traînée monde, flèche écran, chevron)

**Files:**
- Create: `src/client/tutorial/TutorialArrow.ts`
- Modify: `src/client/tutorial/TutorialController.ts`

**Interfaces:**
- Consumes: `TutorialUI.ensure` (Task 7), `TutorialTargets` (Task 8).
- Produces: `TutorialArrow.pointAtWorld(part: BasePart): void`, `TutorialArrow.pointAtGui(target: GuiObject): void`, `TutorialArrow.clear(): void`.

- [ ] **Step 1: Écrire `TutorialArrow`**

`src/client/tutorial/TutorialArrow.ts` :

```ts
import { Players, RunService, Workspace } from "@rbxts/services";
import { TutorialUI } from "./TutorialUI";

// Le pointage du tutorial. Deux modes :
//   • monde  → une TRAÎNÉE de BillboardGui du joueur jusqu'à la cible, qui s'allument
//              l'une après l'autre (chenillard), plus un chevron de bord d'écran quand
//              la cible est hors champ (sinon le joueur ne sait pas où tourner).
//   • GUI    → une flèche à côté du rectangle de la cible, orientée vers elle.
// Une seule boucle RenderStepped, active uniquement pendant un step qui pointe.

const ARROW_IMAGE = "rbxassetid://104204322044198";

const ARROW_COUNT = 6; // longueur max de la traînée
const ARROW_SPACING = 8; // studs entre deux flèches
const ARROW_START_OFFSET = 6; // studs devant le joueur pour la première flèche
const ARROW_SIZE = 5; // studs (taille du BillboardGui)
const ARROW_HEIGHT = 3; // studs au-dessus du sol/de la cible
const CHASE_PERIOD = 1.2; // secondes pour un aller de chenillard
const DIM_TRANSPARENCY = 0.75; // flèche "éteinte"

const GUI_ARROW_SIZE = 64; // pixels
const GUI_ARROW_GAP = 12; // pixels entre la flèche et le bord de la cible
const GUI_BOB = 8; // pixels d'oscillation

interface WorldArrow {
	part: Part;
	image: ImageLabel;
}

let worldArrows: WorldArrow[] = [];
let chevron: ImageLabel | undefined;
let guiArrow: ImageLabel | undefined;
let renderConn: RBXScriptConnection | undefined;
let elapsed = 0;

function makeImage(parent: Instance, size: UDim2): ImageLabel {
	const image = new Instance("ImageLabel");
	image.Name = "TutorialArrowImage";
	image.BackgroundTransparency = 1;
	image.Image = ARROW_IMAGE;
	image.Size = size;
	image.AnchorPoint = new Vector2(0.5, 0.5);
	image.Position = new UDim2(0.5, 0, 0.5, 0);
	image.Parent = parent;
	return image;
}

function makeWorldArrow(): WorldArrow {
	// Une part invisible sert d'ancre au BillboardGui (créée côté client : elle n'existe
	// que pour ce joueur).
	const part = new Instance("Part");
	part.Name = "TutorialArrowAnchor";
	part.Size = new Vector3(0.2, 0.2, 0.2);
	part.Transparency = 1;
	part.Anchored = true;
	part.CanCollide = false;
	part.CanQuery = false;
	part.CanTouch = false;
	part.Locked = true;
	part.Parent = Workspace;

	const billboard = new Instance("BillboardGui");
	billboard.Name = "TutorialArrow";
	// Taille en STUDS (offset nul) : la flèche garde sa taille apparente avec la distance.
	billboard.Size = new UDim2(ARROW_SIZE, 0, ARROW_SIZE, 0);
	billboard.AlwaysOnTop = true; // visible même derrière la géométrie de la room
	billboard.LightInfluence = 0; // couleur constante, indépendante de l'éclairage
	billboard.MaxDistance = 500;
	billboard.Adornee = part;
	billboard.Parent = part;

	return { part, image: makeImage(billboard, new UDim2(1, 0, 1, 0)) };
}

function ensureWorldArrows(): void {
	if (worldArrows.size() > 0) return;
	for (let i = 0; i < ARROW_COUNT; i++) worldArrows.push(makeWorldArrow());
}

function ensureChevron(): ImageLabel {
	if (chevron && chevron.Parent !== undefined) return chevron;
	chevron = makeImage(TutorialUI.ensure(), new UDim2(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE));
	chevron.Name = "TutorialChevron";
	return chevron;
}

function ensureGuiArrow(): ImageLabel {
	if (guiArrow && guiArrow.Parent !== undefined) return guiArrow;
	guiArrow = makeImage(TutorialUI.ensure(), new UDim2(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE));
	guiArrow.Name = "TutorialGuiArrow";
	return guiArrow;
}

function stopRender(): void {
	if (renderConn) {
		renderConn.Disconnect();
		renderConn = undefined;
	}
}

// Angle (degrés) du vecteur écran `delta`, avec l'image considérée pointant vers le HAUT
// à 0°.
function angleOf(delta: Vector2): number {
	return math.deg(math.atan2(delta.X, -delta.Y));
}

function characterPosition(): Vector3 | undefined {
	const hrp = Players.LocalPlayer.Character?.FindFirstChild("HumanoidRootPart");
	return hrp?.IsA("BasePart") ? hrp.Position : undefined;
}

export const TutorialArrow = {
	// Traînée monde vers `part` + chevron si la cible est hors champ.
	pointAtWorld(part: BasePart): void {
		TutorialArrow.clear();
		ensureWorldArrows();
		const chev = ensureChevron();
		const camera = Workspace.CurrentCamera;

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			const from = characterPosition();
			const target = part.Position;
			if (!from || !camera) return;

			// Répartition régulière sur la ligne joueur → cible ; la traînée se raccourcit
			// en approchant plutôt que de se densifier.
			const flat = new Vector3(target.X - from.X, 0, target.Z - from.Z);
			const distance = flat.Magnitude;
			const direction = distance > 0.1 ? flat.Unit : new Vector3(0, 0, 1);
			const phase = (elapsed % CHASE_PERIOD) / CHASE_PERIOD;

			for (let i = 0; i < worldArrows.size(); i++) {
				const arrow = worldArrows[i];
				const along = ARROW_START_OFFSET + i * ARROW_SPACING;
				// Au-delà de la cible → flèche masquée (traînée plus courte de près).
				const beyond = along > distance - 1;
				arrow.image.Visible = !beyond;
				if (beyond) continue;

				const pos = from.add(direction.mul(along)).add(new Vector3(0, ARROW_HEIGHT, 0));
				arrow.part.Position = pos;

				// Chenillard : la flèche dont le rang correspond à la phase est pleine, les
				// autres sont estompées.
				const lit = math.floor(phase * worldArrows.size());
				arrow.image.ImageTransparency = i === lit ? 0 : DIM_TRANSPARENCY;

				// Orientation écran : vers la flèche suivante (ou vers la cible pour la
				// dernière visible).
				const nextWorld =
					along + ARROW_SPACING > distance - 1
						? target
						: from.add(direction.mul(along + ARROW_SPACING)).add(new Vector3(0, ARROW_HEIGHT, 0));
				const [here] = camera.WorldToViewportPoint(pos);
				const [next] = camera.WorldToViewportPoint(nextWorld);
				arrow.image.Rotation = angleOf(new Vector2(next.X - here.X, next.Y - here.Y));
			}

			// Chevron de bord d'écran quand la cible n'est pas visible.
			const [screen, onScreen] = camera.WorldToViewportPoint(target);
			if (onScreen) {
				chev.Visible = false;
			} else {
				const viewport = camera.ViewportSize;
				const center = viewport.mul(0.5);
				const toTarget = new Vector2(screen.X - center.X, screen.Y - center.Y);
				const dir = toTarget.Magnitude > 1 ? toTarget.Unit : new Vector2(0, -1);
				const margin = GUI_ARROW_SIZE;
				const clamped = center.add(
					new Vector2(
						math.clamp(dir.X * viewport.X, -center.X + margin, center.X - margin),
						math.clamp(dir.Y * viewport.Y, -center.Y + margin, center.Y - margin),
					),
				);
				chev.Visible = true;
				chev.Position = new UDim2(0, clamped.X, 0, clamped.Y);
				chev.ImageTransparency = 0;
				chev.Rotation = angleOf(dir);
			}
		});
	},

	// Flèche écran posée à gauche du rectangle de la cible, pointant vers elle.
	pointAtGui(target: GuiObject): void {
		TutorialArrow.clear();
		const arrow = ensureGuiArrow();
		arrow.Visible = true;

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			const pos = target.AbsolutePosition;
			const size = target.AbsoluteSize;
			const bob = math.sin(elapsed * 4) * GUI_BOB;
			// À gauche du bord gauche, centrée verticalement, pointant vers la droite (90°).
			arrow.Position = new UDim2(
				0,
				pos.X - GUI_ARROW_GAP - GUI_ARROW_SIZE / 2 + bob,
				0,
				pos.Y + size.Y / 2,
			);
			arrow.Rotation = 90;
		});
	},

	clear(): void {
		stopRender();
		elapsed = 0;
		for (const arrow of worldArrows) arrow.part.Destroy();
		worldArrows = [];
		if (chevron) {
			chevron.Destroy();
			chevron = undefined;
		}
		if (guiArrow) {
			guiArrow.Destroy();
			guiArrow = undefined;
		}
	},
};
```

- [ ] **Step 2: Brancher dans le contrôleur**

Dans `src/client/tutorial/TutorialController.ts`, ajouter les imports :

```ts
import { TutorialArrow } from "./TutorialArrow";
import { TutorialTargets } from "./TutorialTargets";
```

Dans `clearStep`, ajouter avant `TutorialUI.hideBanner();` :

```ts
	TutorialArrow.clear();
```

Et dans `showStep`, après `TutorialUI.setText(step.text);` :

```ts
	// Pointage. Le monde peut yielder (streaming) → task.spawn, et on vérifie que le
	// step n'a pas changé entre-temps avant d'afficher quoi que ce soit.
	const target = step.target;
	if (target.kind === "gui") {
		const gui = TutorialTargets.resolveGui(target.path);
		if (gui) TutorialArrow.pointAtGui(gui);
		else warn(`TutorialController: cible GUI introuvable "${target.path}"`);
	} else if (target.kind === "world") {
		const shownFor = step.id;
		task.spawn(() => {
			const part = TutorialTargets.resolveWorld(target.part);
			const currentId = (player.GetAttribute(STEP_ATTR) as string | undefined) ?? "";
			if (!part || currentId !== shownFor) return;
			TutorialArrow.pointAtWorld(part);
		});
	}
```

- [ ] **Step 3: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 4: Vérifier les flèches**

`forceTutorial = true`, `npm run build`, `start_stop_play`.

Contrôle visuel via MCP `screen_capture` sur le step `go-to-button` : une traînée de flèches part du joueur vers son bouton, une seule flèche pleine à la fois (chenillard), les flèches sont orientées le long du chemin. Tourner la caméra à l'opposé : un chevron apparaît au bord de l'écran, orienté vers le bouton.

Puis en `execute_luau` (`datamodel_type: "Client"`) :

```lua
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local anchors = 0
for _, inst in ipairs(Workspace:GetChildren()) do
	if inst.Name == "TutorialArrowAnchor" then anchors += 1 end
end
local tut = Players.LocalPlayer.PlayerGui:FindFirstChild("TutorialUI")
local chev = tut and tut:FindFirstChild("TutorialChevron")
return string.format("ancres=%d | chevron_present=%s", anchors, tostring(chev ~= nil))
```
Expected: `ancres=6 | chevron_present=true`

Enfin, vérifier le nettoyage : avancer jusqu'à un step GUI (`devGoto` vers `press-start`) et relire.
Expected: `ancres=0 | chevron_present=false` — la traînée monde est bien détruite au changement de step.

- [ ] **Step 5: Remettre le cheat à false et committer**

```bash
grep -n "forceTutorial = false" src/server/modules/CheatConfig.ts
git add src/client/tutorial out/client/tutorial
git commit -m "feat(tutorial): traînée de flèches monde, flèche écran et chevron hors champ"
```

---

## Task 10: Client — focus (dim / highlight) et verrouillage

**Files:**
- Create: `src/client/tutorial/TutorialFocus.ts`
- Create: `src/client/tutorial/TutorialGate.ts`
- Modify: `src/client/tutorial/TutorialController.ts`
- Modify: `src/client/behaviors/RocketLaunchBehavior.ts`

**Interfaces:**
- Consumes: `TutorialUI.ensure` (Task 7), `TutorialTargets` (Task 8).
- Produces:
  - `TutorialFocus.apply(target: GuiObject, mode: TutorialFocus): void`, `TutorialFocus.clear(): void`
  - `TutorialGate.lockGui(target: GuiObject | undefined): void`, `TutorialGate.lockPrompts(except: BasePart | undefined): void`, `TutorialGate.unlock(): void`
  - `RocketLaunchBehavior.setTutorialActive(active: boolean): void` — met le pulse Claim natif en veille.

- [ ] **Step 1: Écrire `TutorialFocus`**

`src/client/tutorial/TutorialFocus.ts` :

```ts
import { RunService } from "@rbxts/services";
import { TutorialFocus as FocusMode } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Mise en avant d'une cible GUI.
//   "dim"       → 4 frames autour du rectangle de la cible : la cible reste CLIQUABLE
//                 (rien par-dessus), tout le reste est couvert par des frames qui
//                 absorbent l'input (Active = true).
//   "highlight" → contour pulsé sur la cible, SANS assombrir (steps en vol : la fusée
//                 doit rester visible). On ne touche JAMAIS à la taille de la cible :
//                 une interruption laisserait le GUI du jeu déformé.

const DIM_COLOR = Color3.fromRGB(0, 0, 0);
const DIM_TRANSPARENCY = 0.55;
const STROKE_NAME = "TutorialHighlightStroke";
const STROKE_COLOR = Color3.fromRGB(255, 226, 92);
const STROKE_MIN = 2;
const STROKE_MAX = 6;
const PULSE_SPEED = 5;

let dimFrames: Frame[] = [];
let stroke: UIStroke | undefined;
let renderConn: RBXScriptConnection | undefined;
let elapsed = 0;

function makeDimFrame(parent: Instance): Frame {
	const frame = new Instance("Frame");
	frame.Name = "TutorialDim";
	frame.BackgroundColor3 = DIM_COLOR;
	frame.BackgroundTransparency = DIM_TRANSPARENCY;
	frame.BorderSizePixel = 0;
	frame.Active = true; // absorbe les clics
	frame.Parent = parent;
	return frame;
}

// Place les 4 bandes autour du rectangle (x, y, w, h) de la cible.
function layoutDim(target: GuiObject): void {
	if (dimFrames.size() < 4) return;
	const pos = target.AbsolutePosition;
	const size = target.AbsoluteSize;

	// haut
	dimFrames[0].Position = new UDim2(0, 0, 0, 0);
	dimFrames[0].Size = new UDim2(1, 0, 0, math.max(pos.Y, 0));
	// bas
	dimFrames[1].Position = new UDim2(0, 0, 0, pos.Y + size.Y);
	dimFrames[1].Size = new UDim2(1, 0, 1, -(pos.Y + size.Y));
	// gauche
	dimFrames[2].Position = new UDim2(0, 0, 0, pos.Y);
	dimFrames[2].Size = new UDim2(0, math.max(pos.X, 0), 0, size.Y);
	// droite
	dimFrames[3].Position = new UDim2(0, pos.X + size.X, 0, pos.Y);
	dimFrames[3].Size = new UDim2(1, -(pos.X + size.X), 0, size.Y);
}

export const TutorialFocus = {
	apply(target: GuiObject, mode: FocusMode): void {
		TutorialFocus.clear();
		const gui = TutorialUI.ensure();

		if (mode === "dim") {
			for (let i = 0; i < 4; i++) dimFrames.push(makeDimFrame(gui));
			layoutDim(target);
		}

		const outline = new Instance("UIStroke");
		outline.Name = STROKE_NAME;
		outline.Color = STROKE_COLOR;
		outline.Thickness = STROKE_MIN;
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		outline.Parent = target;
		stroke = outline;

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			if (stroke) {
				const t = (math.sin(elapsed * PULSE_SPEED) + 1) / 2;
				stroke.Thickness = STROKE_MIN + (STROKE_MAX - STROKE_MIN) * t;
			}
			// La cible peut bouger/se redimensionner (layouts, tweens) → on suit.
			if (dimFrames.size() > 0) layoutDim(target);
		});
	},

	clear(): void {
		if (renderConn) {
			renderConn.Disconnect();
			renderConn = undefined;
		}
		elapsed = 0;
		for (const frame of dimFrames) frame.Destroy();
		dimFrames = [];
		if (stroke) {
			stroke.Destroy();
			stroke = undefined;
		}
	},
};
```

- [ ] **Step 2: Écrire `TutorialGate`**

`src/client/tutorial/TutorialGate.ts` :

```ts
import { Workspace } from "@rbxts/services";
import { TutorialUI } from "./TutorialUI";

// Verrouillage des interactions hors-scope pendant un step. 100 % client : c'est de
// l'UX, pas de la sécurité (le tutorial ne donne rien de plus que le jeu normal, et le
// serveur valide de toute façon chaque action).
//
// L'état d'origine de chaque instance touchée est mémorisé et restauré — jamais de
// valeur "par défaut" réécrite à l'aveugle.

const lockedButtons = new Map<GuiButton, boolean>();
const lockedPrompts = new Map<ProximityPrompt, boolean>();

export const TutorialGate = {
	// Rend non-interactifs tous les GuiButton de InGameUI SAUF la cible et ses
	// descendants/ancêtres (le dim absorbe déjà la souris ; ceci couvre clavier/manette).
	lockGui(target: GuiObject | undefined): void {
		const root = TutorialUI.getInGameUI();
		if (!root) return;

		for (const descendant of root.GetDescendants()) {
			if (!descendant.IsA("GuiButton")) continue;
			const isTarget =
				target !== undefined && (descendant === target || descendant.IsDescendantOf(target));
			// Le bouton Skip doit rester cliquable en permanence.
			const isSkip = descendant.FindFirstAncestor("TutorialSkip") !== undefined;
			if (isTarget || isSkip) continue;

			if (!lockedButtons.has(descendant)) lockedButtons.set(descendant, descendant.Interactable);
			descendant.Interactable = false;
		}
	},

	// Désactive tous les ProximityPrompt sauf celui de `except` : le joueur ne peut pas
	// entrer dans la boutique avant l'heure. RoomPromptController reprend la main quand
	// on restaure.
	lockPrompts(except: BasePart | undefined): void {
		for (const descendant of Workspace.GetDescendants()) {
			if (!descendant.IsA("ProximityPrompt")) continue;
			if (except !== undefined && descendant.Parent === except) continue;
			if (!descendant.Enabled) continue;
			if (!lockedPrompts.has(descendant)) lockedPrompts.set(descendant, descendant.Enabled);
			descendant.Enabled = false;
		}
	},

	unlock(): void {
		for (const [button, interactable] of lockedButtons) {
			if (button.Parent !== undefined) button.Interactable = interactable;
		}
		lockedButtons.clear();

		for (const [prompt, enabled] of lockedPrompts) {
			if (prompt.Parent !== undefined) prompt.Enabled = enabled;
		}
		lockedPrompts.clear();
	},
};
```

- [ ] **Step 3: Mettre le pulse Claim natif en veille**

Dans `src/client/behaviors/RocketLaunchBehavior.ts`, ajouter près des autres états de module :

```ts
// Pendant le tutorial c'est lui qui met le bouton Claim en avant (TutorialFocus) : deux
// animations concurrentes sur le même bouton se battraient.
let tutorialActive = false;
```

Ajouter à l'export du module (à côté des autres fonctions exportées) :

```ts
export function setTutorialActive(active: boolean): void {
	tutorialActive = active;
	if (active) stopClaimPulse();
}
```

Et, dans `startClaimPulse`, sortir immédiatement quand le tutorial est actif — ajouter en première ligne de la fonction :

```ts
	if (tutorialActive) return;
```

> Si `stopClaimPulse` / `startClaimPulse` ne sont pas au même niveau de portée que le nouvel export, garder `setTutorialActive` dans le même fichier et n'exporter que lui — ne pas déplacer le pulse existant.

- [ ] **Step 4: Brancher dans le contrôleur**

Dans `src/client/tutorial/TutorialController.ts`, ajouter les imports :

```ts
import { TutorialFocus } from "./TutorialFocus";
import { TutorialGate } from "./TutorialGate";
import { setTutorialActive } from "client/behaviors/RocketLaunchBehavior";
```

Dans `clearStep`, avant `TutorialUI.hideBanner();` :

```ts
	TutorialFocus.clear();
	TutorialGate.unlock();
```

Dans `showStep`, dans la branche `target.kind === "gui"`, après `TutorialArrow.pointAtGui(gui);` :

```ts
			if (step.focus !== undefined) {
				TutorialFocus.apply(gui, step.focus);
				TutorialGate.lockGui(gui);
			}
```

et dans la branche monde, après `TutorialArrow.pointAtWorld(part);` :

```ts
			TutorialGate.lockPrompts(part); // seul le prompt de la cible reste actif
```

Ajouter enfin la branche des steps **sans cible** (`kind === "none"`), à la suite du `else if` monde :

```ts
	} else {
		// Steps sans cible (watch-launch, claim-explode) : rien à pointer, mais tout doit
		// rester verrouillé. C'est ce qui bloque "Go Home" pendant le step post-claim —
		// un clic chanceux dans la fenêtre de re-arm sauterait l'explosion que le tutorial
		// veut montrer — et empêche un claim prématuré avant le gel.
		// Le bouton Skip est explicitement épargné par lockGui.
		TutorialGate.lockGui(undefined);
	}
```

Dans `render`, signaler l'état du tutorial au comportement du Claim :

```ts
	if (stepId === "") {
		clearStep();
		setTutorialActive(false);
		TutorialSkipButton.setVisible(false);
		TutorialUI.destroy();
		return;
	}
	...
	setTutorialActive(true);
	TutorialSkipButton.setVisible(true);
	showStep(step);
```

- [ ] **Step 5: Compiler**

Run: `npm run build`
Expected: aucune sortie.

- [ ] **Step 6: Vérifier le focus et le verrouillage**

`forceTutorial = true`, `npm run build`, `start_stop_play`, puis aller au bouton pour ouvrir le `ButtonMenu` (step `press-start`).

Contrôle visuel (`screen_capture`) : l'écran est assombri **sauf** le `StartButton`, qui porte un contour jaune pulsé.

Puis en `execute_luau` (`datamodel_type: "Client"`) :

```lua
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local tut = gui:FindFirstChild("TutorialUI")
local inGame = gui:FindFirstChild("InGameUI")
local dim = 0
for _, inst in ipairs(tut:GetChildren()) do
	if inst.Name == "TutorialDim" then dim += 1 end
end
local start = inGame.ButtonMenu.StartButton
local quit = inGame.ButtonMenu.QuitButton
local skip = gui:FindFirstChild("TutorialSkip", true)
local skipButton = skip and skip:FindFirstChild("TextButton", true)
return string.format(
	"bandes_dim=%d | contour_cible=%s | cible_cliquable=%s | quit_bloque=%s | skip_cliquable=%s",
	dim,
	tostring(start:FindFirstChild("TutorialHighlightStroke") ~= nil),
	tostring(start.Interactable),
	tostring(quit.Interactable == false),
	tostring(skipButton and skipButton.Interactable)
)
```
Expected: `bandes_dim=4 | contour_cible=true | cible_cliquable=true | quit_bloque=true | skip_cliquable=true`

Vérifier la restauration : `devGoto` vers `go-to-button` puis relire.
Expected: `bandes_dim=0 | contour_cible=false | cible_cliquable=true | quit_bloque=false | skip_cliquable=true` — rien n'est resté verrouillé.

Vérifier le blocage de « Go Home » sur un step sans cible : `devGoto` vers `claim-explode`, puis en `execute_luau` client :

```lua
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local claim = gui.InGameUI.RocketLaunch.ClaimButtonFrame.ClaimButton
local skipButton = gui:FindFirstChild("TutorialSkip", true):FindFirstChild("TextButton", true)
return string.format(
	"claim_bloque=%s | skip_cliquable=%s",
	tostring(claim.Interactable == false), tostring(skipButton.Interactable)
)
```
Expected: `claim_bloque=true | skip_cliquable=true` — le Go Home est hors d'atteinte, le Skip reste disponible.

Vérifier enfin qu'aucun `ProximityPrompt` ne reste désactivé après la fin du tutorial : cliquer Skip, puis
```lua
local Workspace = game:GetService("Workspace")
local shopPrompt = Workspace.Shop.ProximityPromptPart.ProximityPrompt
return string.format("shop_prompt_actif=%s", tostring(shopPrompt.Enabled))
```
Expected: `shop_prompt_actif=true`

- [ ] **Step 7: Remettre le cheat à false et committer**

```bash
grep -n "forceTutorial = false" src/server/modules/CheatConfig.ts
git add src/client/tutorial src/client/behaviors/RocketLaunchBehavior.ts out/client/tutorial out/client/behaviors/RocketLaunchBehavior.luau
git commit -m "feat(tutorial): focus dim/highlight, verrouillage des boutons et des prompts"
```

---

## Task 11: Documentation et validation de bout en bout

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `docs/superpowers/specs/2026-08-17-tutorial-system-design.md` (arborescence client réelle)

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: documentation à jour.

- [ ] **Step 1: Jouer le tutorial en entier, sans triche de parcours**

`forceTutorial = true` **et** `resetData = true`, `npm run build`, `start_stop_play`. Jouer les 8 steps à la main, dans l'ordre, sans `devGoto`.

Cocher chaque point (checklist §14 du spec) :

- [ ] traînée de flèches vers **sa** room, chenillard visible, chevron hors champ
- [ ] `press-start` : dim + contour sur START, Quit bloqué
- [ ] gel à 2,5 s : moteur éteint, son coupé, **multiplicateur figé**
- [ ] claim → fusée relancée, explosion **~1 s** après
- [ ] argent crédité = montant affiché
- [ ] `go-to-shop` : prompt boutique accessible, prompt bouton désactivé
- [ ] `ARocketSpeed` affiche **25 $**, puis **50 $** après le 1er achat
- [ ] step passe au 1er achat, boutique toujours utilisable pour le 2e
- [ ] `back-to-button` : déclencher le bouton termine le tutorial (attribut vide)
- [ ] 2e run : explosion **aléatoire** (relancer 2-3 runs pour le confirmer)
- [ ] Skip cliquable **pendant** le run guidé
- [ ] mobile : `resize_window`-équivalent non disponible en Studio → vérifier au moins l'émulateur d'appareil Studio si accessible, sinon noter la limite dans le rapport

- [ ] **Step 2: Vérifier l'inertie hors tutorial**

`forceTutorial = false`, `resetData = false`, `npm run build`, `start_stop_play` avec une save `done` (celle du Step 1).

```lua
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local gui = player.PlayerGui
local skip = gui:FindFirstChild("TutorialSkip", true)
return string.format(
	"step=%s | tutorialUI=%s | skip_visible=%s",
	tostring(player:GetAttribute("TutorialStep")),
	tostring(gui:FindFirstChild("TutorialUI") ~= nil),
	tostring(skip and skip.Visible)
)
```
Expected: `step= | tutorialUI=false | skip_visible=false`

- [ ] **Step 3: Mettre à jour `ARCHITECTURE.md`**

Trois éditions :

1. **§6.8** — corriger les noms de frames périmés : remplacer `AButtonMoney` par `BButtonMoney` et `CRocketSpeed` par `ARocketSpeed` (Studio et `ShopConfig.ts` disent déjà ceci), et documenter les prix imposés :

```
  - Curves: BaseCash `floor(100 * 1.2^level)`, RocketSpeed `1 + level` (integer, uncapped),
    Resistance `level` (plain integer, `maxLevel` 100). Start prices **50 / 75 / 150**
    (BaseCash / RocketSpeed / Resistance), price growth **1.8 / 1.7 / 1.35** per stat.
    **RocketSpeed impose les prix de ses 2 premiers niveaux (25 $ / 50 $ via
    `ROCKET_SPEED.firstLevelPrices`)** pour que l'onboarding tienne dans le gain du
    premier run guidé — au-delà la courbe reprend (L2→3 = 216 $).
```

2. **§8 (tableau des constantes)** — ajouter la ligne :

```
| `ROCKET_SPEED.firstLevelPrices` | `shared/ShopBalance.ts` | [25, 50] | Prix imposés des 2 premiers niveaux (onboarding, §6.20) |
```

3. **Nouvelle section §6.20** juste après §6.19, résumant : les 3 dossiers `tutorial/`, l'attribut `TutorialStep` + `TutorialAdvanceEvent`, le run truqué (`TutorialHooks.beginRun` → `ScriptedRunHandle`, `RocketLauncher.freeze/unfreeze`), le store `PlayerTutorial_v1`, le bouton Skip Studio, le funnel `"Tutorial"` + les 4 compteurs, `forceTutorial` / `devRestart` / `devGoto`, et un renvoi vers le spec. Ajouter aussi `TutorialAdvanceEvent` au **catalogue d'events §7** et `forceTutorial` à la **liste des cheats §9**.

- [ ] **Step 4: Aligner l'arborescence du spec sur le réel**

Dans `docs/superpowers/specs/2026-08-17-tutorial-system-design.md` §1, le bloc `src/client/tutorial/` doit lister les fichiers réellement créés — ajouter `TutorialTargets.ts` (résolution des cibles) et `TutorialTriggers.ts` (détection des complétions), qui sont un découpage du contrôleur pour garder chaque fichier focalisé.

- [ ] **Step 5: Vérifier l'état final du dépôt**

Run:
```bash
git status --short && grep -n "forceTutorial = false" src/server/modules/CheatConfig.ts && grep -n "resetData = false" src/server/modules/CheatConfig.ts && npm run build && node tools/economy-sim.js | tail -5 && git branch --show-current
```
Expected: aucun cheat à `true`, build silencieux, simulateur vert, branche `Tutorial`.

- [ ] **Step 6: Commit**

```bash
git add ARCHITECTURE.md docs/superpowers/specs/2026-08-17-tutorial-system-design.md
git commit -m "docs: documenter le système de tutorial et corriger les noms de frames du shop"
```

---

## Notes pour l'exécutant

- **Ne jamais** merger, pousser, ni ouvrir de PR : la branche `Tutorial` reste locale, le dev s'en charge.
- **Écart assumé au spec §5** : le spec annonçait « une seule boucle RenderStepped pour toute l'UI tuto ». Le plan en a **deux** (une dans `TutorialArrow`, une dans `TutorialFocus`), toutes deux actives seulement pendant un step qui pointe ou qui met en avant. Les fusionner obligerait les deux modules à se connaître ; deux boucles très légères sont préférables à ce couplage. Ne pas « corriger » cet écart sans en parler.
- Si une sonde Studio ne peut pas tourner (Studio non connecté, `start_stop_play` indisponible), **le dire dans le rapport de tâche** au lieu de déclarer la tâche validée. Une tâche dont la vérification n'a pas pu s'exécuter est incomplète, pas terminée.
- Les cheats `forceTutorial` / `resetData` doivent être à `false` dans **chaque** commit ; ils ne sont passés à `true` que le temps d'une vérification locale.
- Si un point du spec s'avère infaisable tel quel (API absente, comportement Roblox différent), s'arrêter et le remonter avec la sortie exacte de la sonde — ne pas improviser une architecture parallèle.
