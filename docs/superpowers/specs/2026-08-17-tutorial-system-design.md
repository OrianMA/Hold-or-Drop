# Système de tutorial — Design

Date : 2026-08-17

## Objectif

Un tutorial qui **contrôle totalement** la première expérience : indiquer où aller (flèche),
mettre en avant l'élément à utiliser (highlight + dim), verrouiller le reste, et **truquer le
premier run** (arrêter la fusée / la faire exploser à un instant fixe) pour que la démonstration
soit toujours la même.

Contraintes posées :

1. **Zéro impact sur le jeu de base.** Le tuto est un satellite, supprimable d'un bloc.
2. **Progression persistée** — pas de tuto rejoué, pas de tuto sauté par un relog.
3. **Cheat de forçage**, utilisable avec `resetData`.

Décisions validées : blocage `dim + focus` réglable par step · tuto pour tout joueur sans le flag
`done` (donc aussi les joueurs actuels) · UI créée **en code**, 100 % client · **bouton Skip**
discret.

Les steps eux-mêmes ne sont **pas** dans ce design : le système est agnostique, la liste arrive
ensuite dans `shared/tutorial/TutorialSteps.ts` (schéma en §4).

## 1. Architecture

```
src/shared/tutorial/
├── TutorialTypes.ts      # Step / Target / Trigger / ScriptedRun (types purs)
└── TutorialSteps.ts      # LA liste ordonnée des steps — le seul fichier à éditer

src/server/tutorial/
├── TutorialService.ts    # étape courante, avancement, persistance, attribut TutorialStep
└── TutorialHooks.ts      # API lue par le jeu de base (inerte si le joueur n'est pas en tuto)

src/client/tutorial/
├── TutorialController.ts # lit l'attribut → orchestre UI + gating, détecte les complétions
├── TutorialUI.ts         # construit le ScreenGui TutorialUI (overlay, flèche, bandeau, Skip)
├── TutorialArrow.ts      # pointage : cible GUI (écran) ou cible monde (BillboardGui)
├── TutorialFocus.ts      # dim « troué » + pulse de la cible
└── TutorialGate.ts       # coupe les interactions hors-scope (boutons, prompts)
```

**Responsabilités**

| Côté | Possède |
|---|---|
| Serveur | l'étape courante (source de vérité), la persistance, le run truqué |
| Client | tout le rendu (flèche/dim/texte), le gating, la détection des complétions |
| Shared | les types + la liste des steps (les deux côtés lisent la même liste) |

## 2. Réseau : 1 attribut + 1 RemoteEvent

- **`TutorialStep` (attribut joueur, S→C)** — l'id du step courant, `""` = terminé. Replication
  standard, cohérent avec §7 d'`ARCHITECTURE.md` (« préférer les Attributes »). Le client réagit
  à `GetAttributeChangedSignal("TutorialStep")`.
- **`TutorialAdvanceEvent` (C→S, arg : `stepId: string`)** — le client signale que la condition du
  step est remplie. Le serveur **ignore l'event si l'id ne correspond pas au step courant** (anti
  double-avance / event en retard), sinon il avance et sauvegarde. Un `stepId` spécial `"skip"`
  termine le tuto (bouton Skip).

Aucun autre event. Les complétions sont détectées avec ce que le client **voit déjà** : events
serveur existants (`ClaimAcceptedEvent`, `EndGameStartEvent`, `ButtonTriggerEvent`…), attributs
répliqués (`Money`, `BaseCashLevel`, `Rebirths`, `InSession`…), visibilité des popups.

## 3. Le run truqué (`ScriptedRun`)

Un step peut porter un `ScriptedRun`. `TutorialHooks.getScriptedRun(player)` le renvoie (ou
`undefined` hors tuto). `ButtonInGameModule.startButtonGame` change de **deux lignes** :

```ts
const scripted = TutorialHooks.getScriptedRun(player); // undefined hors tuto
const explosionAt = scripted?.explodeAt ?? (invincible ? math.huge : rollExplosionTime(riskParams));
// … après RocketLauncher.launch(room, rocketSpeed) :
if (scripted?.stopAt !== undefined) task.delay(scripted.stopAt, () => RocketLauncher.stop(room));
```

- `explodeAt` remplace le tirage — l'explosion tombe **exactement** à cet instant (le loop
  planifié le gère déjà : il attend `explosionAt` sans le dépasser).
- `stopAt` fige l'ascension : le multiplicateur suit la vélocité, donc il se **figera aussi**, ce
  qui laisse au joueur un temps calme pour lire l'instruction et cliquer Claim.
- `noRisk: true` = `explodeAt: math.huge` (run libre, jamais d'explosion) pour un step
  d'exploration.

Rien d'autre n'est touché : résistance, claim, Go Home, payout, analytics restent le chemin normal.
Le run truqué **paie normalement** (c'est de l'argent réel gagné, le joueur n'est pas floué).

## 4. Schéma d'un step

```ts
// shared/tutorial/TutorialTypes.ts
export type TutorialTarget =
  | { kind: "gui"; path: string }          // chemin sous InGameUI, ex "HUD/BottomList/..."
  | { kind: "world"; part: WorldTargetId } // "RoomButton" | "Shop" | "RebirthButton" | ...
  | { kind: "none" };                      // instruction seule (pas de flèche)

export type TutorialTrigger =
  | { kind: "event"; event: TutorialWatchableEvent } // ClaimAccepted / ButtonTrigger / EndGameStart…
  | { kind: "attribute"; attribute: string; atLeast: number } // Money >= n, BaseCashLevel >= 1…
  | { kind: "popup"; popup: PopupOrMenuName }        // ShopMenu / RebirthMenu ouvert
  | { kind: "prompt"; part: WorldTargetId }          // ProximityPrompt déclenché
  | { kind: "tap" }                                  // « appuie pour continuer »
  | { kind: "delay"; seconds: number };

export type ScriptedRun = {
  readonly explodeAt?: number; // secondes de vol avant explosion (remplace le tirage)
  readonly stopAt?: number;    // secondes avant arrêt de l'ascension
  readonly noRisk?: boolean;   // jamais d'explosion
};

export type TutorialStep = {
  readonly id: string;          // stable — c'est LUI qui est persisté
  readonly text: string;        // instruction (FR)
  readonly target: TutorialTarget;
  readonly focus?: boolean;     // défaut true : dim + blocage hors cible
  readonly run?: ScriptedRun;   // s'applique au run lancé pendant ce step
  readonly complete: TutorialTrigger;
};
```

Ordre = ordre du tableau. L'id étant la clé persistée, **renommer un id = renvoyer les joueurs
concernés au début** ; ajouter/retirer un step au milieu est sans risque (un id absent de la liste
fait repartir le joueur au step 0).

`WorldTargetId`, `PopupOrMenuName` et `TutorialWatchableEvent` sont des **unions fermées** de
chaînes (pas de `string` libre) : elles seront remplies avec les cibles/événements réellement
utilisés par la liste de steps, pour que le compilateur attrape une faute de frappe.

## 5. UI client (créée en code)

Un seul `ScreenGui` **`TutorialUI`** (`ResetOnSpawn = false`, `DisplayOrder` au-dessus de
`InGameUI`, `IgnoreGuiInset = true`), construit une fois par `TutorialUI.ts` :

- **Dim « troué »** — 4 `Frame` semi-transparents (haut / bas / gauche / droite) calculés autour
  du rectangle de la cible. La cible reste **cliquable** (aucun frame par-dessus), tout le reste
  est couvert par des frames qui **absorbent l'input** (`Active = true`). Cible `world` ou
  `none` → dim plein écran allégé (ou aucun dim, réglable par step).
- **Flèche** — un `ImageLabel` qui oscille (tween en boucle, comme `CostTextRotator`).
  Cible `gui` : positionnée au bord du rectangle, orientée vers lui, repositionnée chaque frame
  seulement si le rect a bougé. Cible `world` : un `BillboardGui` attaché à la part visée, plus un
  **chevron de bord d'écran** quand la part est hors champ (le joueur doit savoir où tourner).
- **Bandeau** — le texte du step, bas de l'écran (safe area mobile), + le bouton **Skip** discret.
- Tout est détruit à la fin du tuto (`TutorialStep == ""`) — plus une seule connexion active.

Perf mobile : une seule boucle `RenderStepped` pour toute l'UI tuto, et elle ne tourne que
pendant un step visible.

## 6. Gating (`TutorialGate`)

Purement client — c'est de l'UX, pas de la sécurité (rien à exploiter : le tuto ne donne rien de
plus que le jeu normal).

- **Boutons GUI** : `Interactable = false` sur les `GuiButton` hors cible pendant un step `focus`,
  restaurés à la fin du step (état d'origine mémorisé). Le dim absorbant fait déjà l'essentiel ;
  ceci évite les clics via clavier/manette.
- **ProximityPrompts** : mêmes écritures client-local que `RoomPromptController` /
  `CommunityJoinController` — on désactive les prompts non ciblés pendant un step `focus` et on
  laisse `RoomPromptController` reprendre la main après.
- **Jamais de blocage du mouvement** ni de la caméra : le joueur garde le contrôle de son
  personnage, sinon la démo devient une cinématique.

## 7. Persistance & état serveur

Store **dédié** `PlayerTutorial_v1`, clé `Player_{UserId}`, valeur `{ step: string, done: boolean }` :

- Store séparé ⇒ **aucune migration** ni risque sur `PlayerData_v1` / `PlayerProgression_v2`, et
  la suppression du tuto ne laisse qu'un store orphelin inoffensif.
- Même patron que les autres services : `loadedPlayers` (garde anti-écrasement sur échec de load),
  save sur `PlayerRemoving`, `BindToClose` parallèle, tout en `pcall`.
- Sauvegarde **à chaque avance de step** (les steps sont rares : quelques écritures par joueur, pas
  de risque de throttle) → un crash ne fait pas reprendre le tuto au début.
- `done: true` ⇒ `TutorialStep` reste `""` pour toujours : le module est totalement inerte.
- `TutorialService` s'insère dans `services/index.ts` **après `PlayerProgressionService`**
  (il lira éventuellement `isFirstSession`) et **avant `RoomService`** (le step 1 peut cibler le
  bouton dès l'assignation de la room).

## 8. Cheat

Dans `CheatConfig.ts` :

```ts
// Force le tutorial à la connexion, en ignorant la sauvegarde tuto.
// À utiliser avec `resetData` pour re-tester l'onboarding complet.
export const forceTutorial = false;
```

Plus une fonction dev appelable depuis la barre de commande / `execute_luau`, sur le modèle de
`BoostService.devOwn` : `TutorialService.devRestart(player)` (repart au step 0) et
`TutorialService.devGoto(player, stepId)` (saute directement à un step pour tester sa mise en
scène sans refaire tout le tuto).

## 9. Points de contact avec le jeu de base

| Fichier | Changement | Retour arrière |
|---|---|---|
| `server/modules/ButtonInGameModule.ts` | 2 lignes (`explosionAt` + `stopAt`) | révert des 2 lignes |
| `server/services/index.ts` | `TutorialService` dans la liste | 1 ligne |
| `client/main.client.ts` | `initTutorial()` | 1 ligne |
| `server/modules/CheatConfig.ts` | `forceTutorial` | 1 constante |
| `shared/Event.ts` | `TutorialAdvanceEvent` | 1 déclaration |

**Suppression du tuto** = supprimer les 3 dossiers `tutorial/` + révert de ce tableau. Aucun autre
fichier n'importe quoi que ce soit du tuto, aucun `if (tutorial)` dispersé.

## 10. Vérification

Pas de framework de test dans le projet : validation en Studio (single-player, MCP
`start_stop_play`), avec `forceTutorial = true` + `resetData = true`.

Checklist :

1. Le tuto démarre au join, step 1 affiché, flèche sur la bonne cible.
2. Chaque step avance sur sa vraie condition — et **pas** sur une action hors-scope.
3. Le run truqué explose à `explodeAt` ± un tick (0,5 s) et l'ascension se fige à `stopAt`.
4. Le payout du run truqué crédite bien l'argent (chemin normal).
5. Relog en cours de tuto → reprise au même step.
6. Skip → `done`, UI détruite, plus aucune connexion.
7. `forceTutorial = false` + save `done` → **rien** ne s'affiche, et un run normal retrouve un
   `explosionAt` aléatoire (le hook est inerte).
8. Mobile : bandeau lisible, flèche visible, cible cliquable, dim non bloquant sur la cible.
9. Deux joueurs en même temps, l'un en tuto l'autre non : aucune interférence (état par joueur).
