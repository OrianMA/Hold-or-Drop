# Animations du personnage sur le bouton — Design

Date : 2026-06-23

## Objectif

Jouer les animations du perso le long du flux du jeu de bouton. **4 animations** :

| # | Quand | Type | Asset |
|---|---|---|---|
| 1 | Interagit avec le bouton (menu ouvert) | Bouclée | `123442755794873` ("hand on button") |
| 2 | Start la game (appuie et reste dessus) | Bouclée | *(TBD, doit appartenir au groupe)* |
| 3 | Relâche le bouton | Une fois | *(TBD)* |
| 4 | Perfect parry (projection) | Une fois | *(TBD — l'ancien `6481315203` est inutilisable, voir ci-dessous)* |

## ⚠️ Prérequis bloquant — propriété d'asset

Une animation ne se charge **que si son créateur = le créateur de l'expérience**. Le jeu
appartient au **Groupe `963505568`**. Une animation possédée par un compte User échoue
silencieusement : `track.Length = 0`, rien de visible, et la console logge :

```
The experience doesn't have access permission to use asset id <id>.
```

→ Chaque ID des 4 animations doit être **possédé par / partagé avec le groupe `963505568`**
(ré-upload avec le groupe comme créateur, ou partage d'accès via Creator Hub). C'était la
cause racine initiale : `78703307350785` était sous un compte User → ré-uploadé en
`123442755794873` (groupe) → charge (0.7 s). L'ancien candidat parry `6481315203` est créé
par un User tiers → ne charge pas, à remplacer.

## Architecture

### `src/client/behaviors/ButtonAnimations.ts` (nouveau)

Contrôleur 100 % client, anims jouées en priorité `Action` par-dessus l'idle par défaut.

- `ANIM_IDS` : table des 4 ids. **Un id vide est un no-op volontaire** (les autres anims
  continuent de marcher pendant qu'on remplit les ids manquants).
- Tracks chargées paresseusement sur l'`Animator` du perso courant ; cache vidé au respawn.
- `playInteract()` / `playHold()` → poses **bouclées** : une seule tenue à la fois
  (`currentLoop`), stoppe la précédente.
- `playRelease()` / `playParry()` → **one-shot** : stoppent la boucle puis jouent une fois ;
  **non suivies** par `stop()`, donc la fin de partie ne les coupe pas.
- `stop()` → stoppe uniquement la boucle courante (idempotent).

### Points d'appel

| Fichier | Événement | Appel |
|---|---|---|
| `ButtonMenuBehavior` | `ButtonTriggerEvent` | `playInteract()` |
| `ButtonMenuBehavior` | Quit `Activated` | `stop()` |
| `ButtonInGameBehavior` | `setup()` (Start) | `playHold()` |
| `ButtonInGameBehavior` | `fireRelease` | `playRelease()` |
| `ButtonInGameBehavior` | `PerfectParryEffectEvent` | `playParry()` |
| `ButtonInGameBehavior` | `GameResultEvent` | `stop()` (filet mort sans release/parry) |

Transitions : interact → hold → (release **ou** parry **ou** mort). `playHold` stoppe la pose
interact ; `stop()` sur `GameResultEvent` est un no-op après une release/parry (la boucle est
déjà stoppée) et ne coupe donc jamais le one-shot.

## Nettoyage effectué

Suppression du code parry mort dans `ButtonInGameBehavior` : `ANIM_PARRY_ID`
(`6481315203`, inaccessible), la variable `parryAnimTrack`, et le bloc d'anim commenté —
remplacés par `ButtonAnimations.playParry()`.

## Vérification

- Asset `123442755794873` : `GetProductInfo` → créateur Groupe `963505568`, type 24
  (Animation). Chargé en jeu : `Length = 0.7 s`, `IsPlaying = true`, aucune erreur console.
- Module synchronisé (Rojo) testé en jeu via le **vrai** module :
  `playInteract()` → track `123442755794873` joue (looped) ; `playHold()` (id vide) →
  l'interact s'arrête, rien d'autre ne joue ; `stop()` → propre. 0 erreur console.

## Reste à faire

Fournir les ids **groupe-owned** pour #2 (hold), #3 (release), #4 (parry) → les coller dans
`ANIM_IDS`. Le câblage et les transitions sont déjà en place.
