# Système de tutorial — Design

Date : 2026-08-17
Branche : **`Tutorial`** — pas de merge ni de PR depuis cette session, le dev s'en charge.

## Objectif

Un tutorial qui **contrôle totalement** la première expérience : indiquer où aller (flèches),
mettre en avant l'élément à utiliser, verrouiller le reste, et **truquer le premier run** (geler la
fusée, la faire exploser 1 s après le claim) pour que la démonstration soit toujours identique.

Contraintes posées :

1. **Zéro impact sur le jeu de base.** Le tuto est un satellite, supprimable d'un bloc.
2. **Progression persistée** — pas de tuto rejoué, pas de tuto sauté par un relog.
3. **Cheat de forçage**, utilisable avec `resetData`.

Décisions validées : focus réglable par step · tuto pour tout joueur sans le flag `done` (donc
aussi les joueurs actuels) · UI créée **en code**, 100 % client, **sauf le bouton Skip** authoré
dans Studio (§6) · analytics détaillées (§9) · démarrage direct sur les flèches (pas de panneau
d'accueil) · **traînée de flèches en chenillard** pour les cibles monde · l'étape boutique passe au
1er achat · le tuto se termine quand le joueur redéclenche son bouton.

## 1. Architecture

```
src/shared/tutorial/
├── TutorialTypes.ts        # Step / Target / Trigger / ScriptedRun (types purs)
└── TutorialSteps.ts        # LA liste ordonnée des steps (§10) — le fichier à éditer

src/server/tutorial/
├── TutorialService.ts      # étape courante, avancement, persistance, attribut TutorialStep
├── TutorialRunDirector.ts  # met en scène le run truqué (gel, reprise, explosion)
├── TutorialAnalytics.ts    # sémantique analytics du tuto (funnel + compteurs)
└── TutorialHooks.ts        # API lue par le jeu de base (inerte hors tuto)

src/client/tutorial/
├── TutorialController.ts   # lit l'attribut → orchestre UI + gating, détecte les complétions
├── TutorialUI.ts           # construit le ScreenGui TutorialUI (overlay, bandeau)
├── TutorialArrow.ts        # traînée de flèches monde (BillboardGui) + flèche écran
├── TutorialFocus.ts        # dim « troué » / highlight + pulse de la cible
├── TutorialSkipButton.ts   # pilote le bouton Skip authoré dans Studio (§6)
└── TutorialGate.ts         # coupe les interactions hors-scope (boutons, prompts)
```

**Responsabilités**

| Côté | Possède |
|---|---|
| Serveur | l'étape courante (source de vérité), la persistance, la mise en scène du run |
| Client | tout le rendu (flèches/dim/texte), le gating, la détection des complétions |
| Shared | les types + la liste des steps (les deux côtés lisent la même liste) |

## 2. Réseau : 1 attribut + 1 RemoteEvent

- **`TutorialStep` (attribut joueur, S→C)** — l'id du step courant, `""` = terminé. Replication
  standard, cohérent avec §7 d'`ARCHITECTURE.md` (« préférer les Attributes »). Le client réagit
  à `GetAttributeChangedSignal("TutorialStep")`.
- **`TutorialAdvanceEvent` (C→S, arg : `stepId: string`)** — le client signale que la condition du
  step est remplie. Le serveur **ignore l'event si l'id ne correspond pas au step courant** (anti
  double-avance / event en retard), sinon il avance et sauvegarde. Un `stepId` spécial `"skip"`
  termine le tuto.

Les steps dont le déclencheur est **serveur** (`{ kind: "server" }`, §4) avancent sans passer par
cet event : le serveur sait déjà (il vient de geler la fusée).

Aucun autre event. Les complétions client sont détectées avec ce que le client **voit déjà** :
events serveur existants (`ClaimAcceptedEvent`, `EndGameFinishedEvent`, `ButtonTriggerEvent`…),
attributs répliqués (`Money`, `RocketSpeedLevel`…), visibilité des popups.

## 3. Le run truqué (`TutorialRunDirector`)

Le scénario demandé : la fusée décolle, **se gèle à 2,5 s**, et le claim la **relance** puis la fait
**exploser 1 s après**. L'instant d'explosion n'est donc pas connu au décollage — il dépend du
claim. Le loop actuel fixe `explosionAt` une fois pour toutes ; on le rend interrogeable.

### 3.1 Contact avec `ButtonInGameModule`

```ts
// au début de startButtonGame — undefined hors tuto ; sinon le director démarre son scénario
// (timer de gel, avance du step) et expose la deadline d'explosion, qu'il peut réécrire.
const scripted = TutorialHooks.beginRun(player, room);
const explosionAt = invincible ? math.huge : rollExplosionTime(riskParams);

// dans le handler de claim, une ligne :
scripted?.onClaim();   // relance la fusée + fixe l'explosion à +1 s

// dans la boucle risque, la deadline est lue via le director quand il y en a un :
const deadline = scripted?.explosionAt() ?? explosionAt;
```

`deadline` remplace `explosionAt` aux deux endroits où la boucle l'utilise déjà
(`math.min(timeHeld + TICK_RATE, deadline)` et `timeHeld >= deadline`). Comme la boucle la relit à
chaque tour et que le délai post-claim (1 s) est supérieur à deux ticks (0,5 s), l'explosion tombe
**exactement** à l'instant voulu.

Toute la logique de mise en scène (quand geler, quand relancer, quel délai) vit dans
`TutorialRunDirector` — `ButtonInGameModule` ne connaît que ces 3 lignes, et le chemin normal
(résistance, claim, Go Home, payout, analytics) est **inchangé**.

### 3.2 Geler la fusée : `RocketLauncher.freeze` / `unfreeze`

`launch()` **ne peut pas** servir à reprendre un vol : il repose la fusée sur le pad
(`resetRoom`). `stop()` détruit l'état de vol. Il faut donc une vraie **pause**, ajoutée à
`RocketLauncher` (~12 lignes, générique, rien d'autre ne l'appelle) :

- un champ `paused: boolean` dans `RocketState` ; le Heartbeat d'ascension `return` tôt quand il
  est vrai (la vélocité acquise est **conservée** pour la reprise) ;
- `freeze(room)` : `paused = true`, moteur éteint (`setNitroEnabled(false)`), son de décollage en
  pause → la fusée est visiblement figée, en vol ;
- `unfreeze(room)` : l'inverse, l'ascension reprend à la vélocité qu'elle avait ;
- `getVelocity(room)` renvoie **0** quand la fusée est gelée. Conséquence gratuite et voulue : le
  multiplicateur (qui suit la distance montée) **se figera aussi** pendant le gel, ce qui laisse au
  joueur un temps calme pour lire l'instruction et viser le bouton Claim.

### 3.3 Champs du `ScriptedRun`

| Champ | Effet |
|---|---|
| `freezeAt` | gèle l'ascension à t secondes après le décollage |
| `unfreezeOnClaim` | le claim relance l'ascension |
| `explodeAfterClaim` | explosion N secondes après le claim |
| `explodeAt` | explosion à t fixe depuis le décollage (scénarios sans claim) |
| `noRisk` | aucun tirage aléatoire : la seule explosion possible est celle du script |

Le `ScriptedRun` est lu **une seule fois, au décollage**, sur le step courant, puis conservé pour
tout le run : les avances de step pendant le vol ne changent pas le scénario en cours (pas de
course entre l'avance de step et la boucle de jeu).

Le run truqué **paie normalement** : le gain est du vrai argent, par le chemin de payout habituel.

## 4. Schéma d'un step

```ts
// shared/tutorial/TutorialTypes.ts
export type TutorialTarget =
  | { kind: "gui"; path: string }          // chemin sous InGameUI, ex "ButtonMenu/StartButton"
  | { kind: "world"; part: WorldTargetId } // "RoomButton" | "Shop"
  | { kind: "none" };                      // instruction seule (aucun pointage)

// Comment la cible est mise en avant :
//   "dim"       → overlay sombre troué + blocage (menus : la vue 3D n'a pas d'importance)
//   "highlight" → pulse + contour + flèche écran, SANS assombrir (steps en vol : la fusée
//                 doit rester visible), boutons hors cible quand même bloqués
//   absent      → aucune mise en avant (steps monde : on pointe, on ne masque rien)
export type TutorialFocus = "dim" | "highlight";

export type TutorialTrigger =
  | { kind: "event"; event: TutorialWatchableEvent } // ClaimAccepted / EndGameFinished / ButtonTrigger…
  | { kind: "attribute"; attribute: string; atLeast: number } // RocketSpeedLevel >= 1…
  | { kind: "popup"; popup: PopupOrMenuName }        // ShopMenu / RebirthMenu ouvert
  | { kind: "prompt"; part: WorldTargetId }          // ProximityPrompt déclenché
  | { kind: "server" }                               // le serveur avance lui-même (run truqué)
  | { kind: "tap" }
  | { kind: "delay"; seconds: number };

export type ScriptedRun = {
  readonly freezeAt?: number;
  readonly unfreezeOnClaim?: boolean;
  readonly explodeAfterClaim?: number;
  readonly explodeAt?: number;
  readonly noRisk?: boolean;
};

export type TutorialStep = {
  readonly id: string;          // stable — c'est LUI qui est persisté
  readonly text: string;        // instruction (FR)
  readonly target: TutorialTarget;
  readonly focus?: TutorialFocus;
  readonly run?: ScriptedRun;   // scénario du run lancé DEPUIS ce step
  readonly complete: TutorialTrigger;
};
```

Ordre = ordre du tableau. L'id étant la clé persistée, **renommer un id = renvoyer les joueurs
concernés au début** ; ajouter/retirer un step au milieu est sans risque (un id absent de la liste
fait repartir le joueur au step 0).

`WorldTargetId`, `PopupOrMenuName` et `TutorialWatchableEvent` sont des **unions fermées** de
chaînes (pas de `string` libre), pour que le compilateur attrape une faute de frappe.

## 5. UI client (créée en code)

Un seul `ScreenGui` **`TutorialUI`** (`ResetOnSpawn = false`, `DisplayOrder` au-dessus de
`InGameUI`, `IgnoreGuiInset = true`), construit une fois :

- **Traînée de flèches (cible monde)** — image **`rbxassetid://104204322044198`**. N `BillboardGui`
  répartis sur la ligne *joueur → cible* (recalculée quand le joueur s'éloigne), qui **s'allument
  l'une après l'autre en boucle** (chenillard : opacité + léger scale), la dernière posée sur la
  cible. Espacement constant en studs, nombre de flèches borné (la traînée se raccourcit en
  approchant, elle ne se densifie pas). Si la cible est **hors champ**, un chevron de bord d'écran
  indique la direction — sinon le joueur ne sait pas où tourner.
- **Flèche écran (cible GUI)** — la même image en `ImageLabel`, posée au bord du rectangle de la
  cible et orientée vers elle, avec une oscillation en boucle (même patron que `CostTextRotator`).
- **Dim « troué »** (`focus: "dim"`) — 4 `Frame` semi-transparents (haut / bas / gauche / droite)
  calculés autour du rectangle de la cible. La cible reste **cliquable** (aucun frame par-dessus),
  tout le reste est couvert par des frames qui **absorbent l'input** (`Active = true`).
- **Highlight** (`focus: "highlight"`) — `UIStroke` + pulse de taille sur la cible, **sans** dim :
  utilisé pendant le vol pour ne jamais masquer la fusée (même patron que le pulse existant du
  Claim dans `RocketLaunchBehavior`, qu'on **désactive** pendant le tuto pour éviter le doublon).
- **Bandeau** — le texte du step, bas de l'écran (safe area mobile). Le Skip n'est pas ici (§6).
- Tout est détruit à la fin du tuto (`TutorialStep == ""`) — plus une seule connexion active.

Perf mobile : une seule boucle `RenderStepped` pour toute l'UI tuto, active seulement pendant un
step visible.

## 6. Bouton Skip (authoré dans Studio)

Vérifié en Studio — hiérarchie réelle :

```
InGameUI/TutorialSkip            (Frame)   ← visibilité pilotée par le code
  └── TutorialSkipFrame          (Frame)   UIStroke, UICorner
        ├── TextButton           (TextButton)  ← le clic écouté
        └── Text                 (TextLabel)
```

`TutorialSkipButton.ts` résout `TutorialSkip` **par nom sous `InGameUI`** (recherche récursive), et
le `TextButton` sous lui — tu peux réorganiser/déplacer le frame sans toucher au code. Il gère :

- `TutorialSkip.Visible = true` pendant le tuto, `false` dès qu'il est fini (et au join si le
  joueur a déjà `done`) ;
- le clic → `TutorialAdvanceEvent("skip")` → le serveur marque `done`.

`TutorialSkip` est déjà **enfant direct de `InGameUI`** (frère du `HUD`) : parfait, il survit donc
au masquage du `HUD` pendant un run actif (§6.7 d'`ARCHITECTURE.md`) et reste cliquable pendant le
run guidé. `ResetOnSpawn = false` est déjà garanti par `InGameUI`, et `UiClickSound` hooke le
bouton automatiquement.

## 7. Gating (`TutorialGate`)

Purement client — c'est de l'UX, pas de la sécurité (rien à exploiter : le tuto ne donne rien de
plus que le jeu normal).

- **Boutons GUI** : `Interactable = false` sur les `GuiButton` hors cible pendant un step
  `dim`/`highlight`, restaurés à la fin du step (état d'origine mémorisé). Couvre les clics
  clavier/manette que le dim n'absorbe pas.
- **ProximityPrompts** : mêmes écritures client-local que `RoomPromptController` /
  `CommunityJoinController` — les prompts non ciblés sont désactivés pendant un step ciblé, et
  `RoomPromptController` reprend la main à la fin du tuto.
- **Go Home** : bloqué pendant le step post-claim (la fenêtre de re-arm ne dure que 0,4 s avant
  l'explosion scriptée, mais un clic chanceux sauterait la démonstration de l'explosion).
- **Jamais de blocage du mouvement** ni de la caméra : le joueur garde le contrôle de son
  personnage — il doit marcher jusqu'au bouton et jusqu'à la boutique.

## 8. Persistance & état serveur

Store **dédié** `PlayerTutorial_v1`, clé `Player_{UserId}` :

```ts
type TutorialSave = {
  step: string;    // id du step courant ("" une fois terminé)
  done: boolean;   // tuto fini (complété OU skippé) → module inerte à vie
  runId: string;   // GUID de la tentative — garde le même funnel analytics après un relog (§9)
  elapsed: number; // secondes cumulées passées dans le tuto, hors temps hors-ligne (§9)
};
```

- Store séparé ⇒ **aucune migration** ni risque sur `PlayerData_v1` / `PlayerProgression_v2`, et
  la suppression du tuto ne laisse qu'un store orphelin inoffensif.
- Même patron que les autres services : `loadedPlayers` (garde anti-écrasement sur échec de load),
  save sur `PlayerRemoving`, `BindToClose` parallèle, tout en `pcall`.
- Sauvegarde **à chaque avance de step** (une poignée d'écritures par joueur, aucun risque de
  throttle) → un crash ne fait pas reprendre le tuto au début.
- `done: true` ⇒ `TutorialStep` reste `""` pour toujours : le module est totalement inerte.
- `TutorialService` s'insère dans `services/index.ts` **après `PlayerProgressionService`** et
  **avant `RoomService`** (le premier step cible le bouton dès l'assignation de la room).

**Mesure du temps** : à l'entrée d'un step le serveur note `stepEnteredAt = os.time()` ; à l'avance
il fait `elapsed += os.time() - stepEnteredAt`. Le temps **hors-ligne n'est jamais compté**.

## 9. Analytics

Tout passe par `AnalyticsService` (server-only, chaque appel en `pcall` — une analytics qui échoue
ne casse jamais le tuto). **Une seule primitive générique est ajoutée au service partagé** :

```ts
// généralise runStep(), qui devient un appel à celle-ci (comportement inchangé)
funnelStep(player: Player, funnelName: string, sessionId: string, step: number, stepName: string): void
```

Toute la sémantique tuto vit dans `server/tutorial/TutorialAnalytics.ts`.

### 9.1 Funnel `"Tutorial"` — chaque step franchi

`funnelSessionId` = le `runId` **persisté** (§8) : un joueur qui se déconnecte au step 3 et revient
reprend **le même funnel**, il ne compte pas comme un second joueur.

- Step loggé **à l'entrée** de chaque step : numéro = `index + 1`, nom = l'id du step.
- Dernière marche = `steps.size() + 1`, nom `"Done"`, loggée à la complétion.
- Conséquence : le **drop-off entre N et N+1 = les joueurs qui abandonnent pendant le step N**. Le
  dashboard donne directement le step qui fait fuir, sans calcul.
- Un re-log du même step après un relog est inoffensif (même `sessionId`, même numéro).

### 9.2 Compteurs custom

| Événement | `value` | Champ de breakdown | Répond à |
|---|---|---|---|
| `TutorialStarted` | 1 | `"Fresh"` \| `"Resumed"` | dénominateur : combien commencent |
| `TutorialStepDone` | secondes passées **sur ce step** | id du step | quel step est long / bloquant |
| `TutorialCompleted` | **durée totale** du tuto (s) | `"NoSkip"` | combien finissent sans skip, et en combien de temps |
| `TutorialSkipped` | durée écoulée avant le skip (s) | **id du step où il a skippé** | combien skippent, et **où** |

### 9.3 Lecture des 4 questions posées

| Question | Où la lire |
|---|---|
| Joueurs qui skippent | compteur `TutorialSkipped` (breakdown = le step de sortie) |
| Temps total du tuto | `value` moyen de `TutorialCompleted` (temps en jeu, hors-ligne exclu) |
| Chaque step passé | funnel `"Tutorial"` (§9.1) + durées via `TutorialStepDone` |
| Finis **sans** skip | `TutorialCompleted` (jamais loggé sur un skip) ; taux = `TutorialCompleted` / `TutorialStarted` |

Le **funnel onboarding existant** (`Joined → Launch → Claim → Purchase → Rebirth`, gaté sur
`isFirstSession`, §6.19 d'`ARCHITECTURE.md`) n'est **pas** touché : funnel distinct, public plus
large pour le tuto. Les deux se lisent côte à côte.

## 10. Les steps

Les 10 points demandés se ramènent à **8 steps** : « player spawn » est la condition de départ (pas
un step), et « rocket speed highlighted » + « player upgrades » sont deux faces du même step.

| # | id | Instruction (FR) | Cible | Focus | Run | Passe quand |
|---|---|---|---|---|---|---|
| 1 | `go-to-button` | « Va appuyer sur ton bouton ! » | monde : `ButtonModel/ButtonPart` de sa room (traînée) | — | — | le ProximityPrompt du bouton est déclenché |
| 2 | `press-start` | « Appuie sur START pour décoller » | GUI : `ButtonMenu/StartButton` | `dim` | `{ freezeAt: 2.5, unfreezeOnClaim: true, explodeAfterClaim: 1, noRisk: true }` | `StartButtonClickedEvent` |
| 3 | `watch-launch` | « Ta fusée décolle ! Plus elle monte, plus ton multiplicateur grimpe » | aucune | — | (run en cours) | **serveur** : au gel de la fusée (2,5 s) |
| 4 | `claim` | « Appuie sur CLAIM pour sécuriser tes gains » | GUI : `RocketLaunch/ClaimButtonFrame/ClaimButton` | `highlight` | (run en cours) | `ClaimAcceptedEvent` |
| 5 | `claim-explode` | « Gains sécurisés ! Même si la fusée explose, tu gardes tout » | aucune | — | (run en cours) | fin du payout (`EndGameFinishedEvent`) |
| 6 | `go-to-shop` | « Direction la boutique pour améliorer ta fusée » | monde : `Workspace/Shop/ProximityPromptPart` (traînée) | — | — | le `ShopMenu` s'ouvre |
| 7 | `buy-rocket-speed` | « Achète Rocket Speed : ta fusée montera plus vite » | GUI : `ShopMenu/Body/ARocketSpeed` | `dim` | — | `RocketSpeedLevel >= 1` |
| 8 | `back-to-button` | « Retourne à ton bouton et rejoue — à toi de jouer ! » | monde : `ButtonModel/ButtonPart` (traînée) | — | — | le prompt du bouton est déclenché → **`done`** |

**Notes de mise en scène**

- **Le run truqué est porté par le step 2** (celui depuis lequel le décollage part), et reste actif
  pour tout le run — voir §3.3.
- Steps 3 et 5 : **pas de focus**, la vue 3D doit rester lisible (fusée, explosion). Step 4 :
  `highlight` et non `dim`, même raison — la fusée gelée reste visible derrière le bouton Claim.
- **Le pulse d'onboarding existant du Claim** (`RocketLaunchBehavior.startClaimPulse`) est mis en
  veille pendant le tuto : le tuto pilote déjà la mise en avant du bouton, deux animations
  concurrentes sur le même bouton se battraient.
- **Économie du step 7** : après le run guidé (gel à 2,5 s → multiplicateur ~×1,09) le joueur a
  ~109 $. Les 2 premiers niveaux de RocketSpeed sont ramenés à **25 $ et 50 $** (§11), soit 75 $
  pour les deux → il peut en acheter **deux** et sentir la différence dès le run suivant. Le step
  passe au 1er achat et le step 8 ne bloque pas la boutique : le 2e achat se fait librement.
- Après le step 8 le 2e run est **entièrement libre** : vrai risque, explosion aléatoire.

## 11. Prix des 2 premiers niveaux de Rocket Speed

Changement d'**économie**, pas de tuto : les 2 premières améliorations passent à **25 $ et 50 $**,
puis la courbe actuelle reprend inchangée.

| Niveau | Avant | Après |
|---|---|---|
| L0 → 1 | 75 $ | **25 $** |
| L1 → 2 | 127 $ | **50 $** |
| L2 → 3 | 216 $ | 216 $ (inchangé) |
| L3 → 4 | 368 $ | 368 $ (inchangé) |

**Implémentation** — un tableau d'exceptions, pas une nouvelle formule :

```ts
// shared/ShopBalance.ts
export const ROCKET_SPEED = {
  baseValue: 1,
  startPrice: 75,
  priceGrowth: 1.7,
  // Prix imposés des premiers niveaux (index = niveau de départ). Au-delà du tableau,
  // la courbe startPrice * priceGrowth ^ level reprend telle quelle. Onboarding : les
  // 2 premières améliorations doivent tenir dans le gain du premier run (~109 $).
  firstLevelPrices: [25, 50],
};

// shared/ShopConfig.ts — priceForLevel consulte le tableau avant la formule
export function priceForLevel(stat: ShopStat, level: number): number {
  const cfg = STATS[stat];
  const override = cfg.firstLevelPrices?.[level];
  if (override !== undefined) return override;
  return math.floor(cfg.startPrice * cfg.priceGrowth ** level);
}
```

`firstLevelPrices` devient un champ optionnel de `StatConfig` (les deux autres stats ne le
définissent pas). Tout le reste passe déjà par `priceForLevel` — affichage client, validation
serveur, `priceForItem` — donc **un seul point de vérité** et aucun risque de désaccord
client/serveur.

**Conséquences assumées**

- Les niveaux resettant à chaque rebirth, les 2 premiers RocketSpeed sont **de nouveau à 25/50 $
  après chaque rebirth**. C'est cohérent avec l'objectif de re-climb rapide du rééquilibrage du
  2026-07-22 (le joueur ne doit pas passer son cycle à racheter l'existant).
- La marche 50 $ → 216 $ se sent au 3e achat. C'est voulu : le mur de progression reste intact,
  seul l'amorçage est offert.
- **`tools/economy-sim.js` doit apprendre le tableau** : il relit `startPrice`/`priceGrowth` dans
  `ShopBalance.ts` et réimplémente la formule, donc il faut y ajouter la lecture de
  `firstLevelPrices` et l'override correspondant, puis relancer `node tools/economy-sim.js` pour
  vérifier que les critères de balance passent toujours.

## 12. Cheat

Dans `CheatConfig.ts` :

```ts
// Force le tutorial à la connexion, en ignorant la sauvegarde tuto.
// À utiliser avec `resetData` pour re-tester l'onboarding complet.
export const forceTutorial = false;
```

Plus deux fonctions dev appelables depuis la barre de commande / `execute_luau`, sur le modèle de
`BoostService.devOwn` : `TutorialService.devRestart(player)` (repart au step 0) et
`TutorialService.devGoto(player, stepId)` (saute à un step pour tester sa mise en scène sans
refaire tout le tuto).

## 13. Points de contact avec le jeu de base

| Fichier | Changement | Retour arrière |
|---|---|---|
| `server/modules/ButtonInGameModule.ts` | 3 lignes (`beginRun`, `onClaim`, `deadline`) + 2 usages de `deadline` | révert des 3 lignes |
| `server/modules/RocketLauncher.ts` | `freeze` / `unfreeze` + champ `paused` (générique, ~12 lignes) | peut rester, personne d'autre ne l'appelle |
| `server/services/AnalyticsService.ts` | helper générique `funnelStep` (`runStep` devient un appel à lui) | peut rester |
| `server/services/index.ts` | `TutorialService` dans la liste | 1 ligne |
| `client/main.client.ts` | `initTutorial()` | 1 ligne |
| `client/behaviors/RocketLaunchBehavior.ts` | pulse Claim en veille pendant le tuto | 1 condition |
| `server/modules/CheatConfig.ts` | `forceTutorial` | 1 constante |
| `shared/Event.ts` | `TutorialAdvanceEvent` | 1 déclaration |
| `shared/ShopBalance.ts` | `ROCKET_SPEED.firstLevelPrices = [25, 50]` (§11) | 1 champ |
| `shared/ShopConfig.ts` | `firstLevelPrices` dans `StatConfig` + `priceForLevel` (§11) | 3 lignes |
| `tools/economy-sim.js` | lit + applique `firstLevelPrices` (§11) | ~5 lignes |
| `ARCHITECTURE.md` | nouvelle section tutorial, prix RocketSpeed (§8), correction §6.8 (`BButtonMoney`/`ARocketSpeed`, périmé) | — |

**Suppression du tuto** = supprimer les 3 dossiers `tutorial/` + révert de ce tableau. Aucun autre
fichier n'importe quoi que ce soit du tuto, aucun `if (tutorial)` dispersé. Le changement de prix
(§11) est **indépendant du tuto** : il reste en place même si le tuto est retiré.

## 14. Vérification

Pas de framework de test dans le projet : validation en Studio (single-player, MCP
`start_stop_play`), avec `forceTutorial = true` + `resetData = true`.

Checklist :

1. Le tuto démarre au spawn, traînée de flèches vers le bouton de **sa** room (pas celle d'un
   voisin), chenillard visible, chevron quand le bouton est hors champ.
2. Chaque step avance sur sa vraie condition — et **pas** sur une action hors-scope.
3. La fusée se gèle à 2,5 s : moteur éteint, son coupé, **multiplicateur figé**.
4. Le claim relance la fusée et l'explosion tombe **1 s après** (± un tick), pas avant.
5. Le payout du run truqué crédite bien l'argent (chemin normal), et le montant affiché = crédité.
6. Le step 7 passe au 1er achat de RocketSpeed ; le step 8 laisse la boutique utilisable, et le
   joueur a bien de quoi acheter le **2e** niveau (25 $ puis 50 $ affichés, et facturés, des deux
   côtés).
7. `node tools/economy-sim.js` passe toujours ses critères après le changement de prix (§11), et le
   3e niveau est bien revenu à 216 $.
8. Step 8 : déclencher le bouton termine le tuto (`done`), et le 2e run a une explosion
   **aléatoire** (le director est inerte).
9. Relog en cours de tuto → reprise au même step, `elapsed` conservé, **même `runId`**.
10. Skip → `done`, UI détruite, `TutorialSkip` masqué, prompts et boutons restaurés.
11. Le Skip reste cliquable **pendant le run guidé** (il est hors du HUD, §6).
12. `forceTutorial = false` + save `done` → **rien** ne s'affiche, `TutorialSkip` invisible, et un
    run normal retrouve un `explosionAt` aléatoire (hook inerte).
13. Mobile : bandeau lisible, flèches visibles, cible cliquable, dim non bloquant sur la cible.
14. Deux joueurs simultanés, l'un en tuto l'autre non : aucune interférence (état par joueur, gel
    d'une room n'affecte pas l'autre).
15. Analytics : les 4 compteurs + le funnel partent (vérifiables via un `print` de debug — le
    dashboard Roblox ne montre rien en Play Solo et met ~24 h, §6.19 d'`ARCHITECTURE.md`). Un tuto
    complété ne logge **jamais** `TutorialSkipped`, et inversement.
