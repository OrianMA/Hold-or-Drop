# Spec — Leaderboards & Podium (classements physiques globaux)

> Date : 2026-06-23
> Statut : design validé, prêt pour plan d'implémentation.

## 1. Objectif

Ajouter dans le monde **deux classements physiques globaux et persistants** + un
**podium** des 3 joueurs les plus riches :

- **Panneau Argent** — top joueurs par `Money` courant (tous serveurs, tout le temps).
- **Panneau Temps de jeu** — top joueurs par **temps de jeu total cumulé** (somme de
  toutes les sessions).
- **Podium** — les 3 premiers du classement argent, sur 3 marches physiques déjà
  amorcées, chacun avec **l'avatar réel** du joueur : le **1er marche** (walk en boucle),
  le **2e et le 3e sont en idle**.

Chaque panneau affiche le **top 50**, dont **15 lignes visibles** à la fois, le reste
**accessible par défilement** (molette / glissé tactile).

## 2. Périmètre

**Inclus**
- 2 classements globaux persistants via **OrderedDataStore**.
- Nouvel accumulateur persistant **temps de jeu total** par joueur.
- Rendu **100 % serveur** (réplication automatique) : SurfaceGui des panneaux + 3 rigs
  du podium (avatars + animations). **0 RemoteEvent, 0 script client.**
- Boucle de rafraîchissement périodique optimisée.
- Construction des pièces Studio manquantes (2 panneaux + rigs 2e/3e, ancrage des marches).

**Exclus (non-goals)**
- Aucune monétisation / récompense liée au fait d'être classé.
- Pas de surlignage « ta ligne » par client (pas de personnalisation par joueur).
- Pas de pagination au-delà de 50 entrées.
- Pas d'anti-triche additionnel : `Money` est déjà serveur-autoritaire ; le temps de jeu
  est mesuré côté serveur (horloge connexion), non transmis par le client.

## 3. Décisions de cadrage (validées)

1. **Argent** = `Money` **courant** (redescend à 0 après un rebirth) — standard des
   leaderboards physiques.
2. **Temps de jeu** = **total cumulé** sur toutes les sessions (pas « une seule partie »).
3. Les deux classements sont **globaux + persistants** (OrderedDataStore).
4. Top 50 stocké/lu, **15 visibles**, défilement pour le reste.
5. Avatars réels sur le podium ; je construis les pièces physiques manquantes dans Studio.

## 4. Modèle de données

### 4.1 OrderedDataStores (index de classement)
- `LB_Money_v1` — clé `tostring(UserId)`, valeur `math.floor(Money)` (clampée ≥ 0).
- `LB_Playtime_v1` — clé `tostring(UserId)`, valeur **temps total en secondes** (entier).

Les OrderedDataStores ne stockent que des nombres : les **noms** sont résolus à part via
`Players:GetNameFromUserIdAsync(userId)` avec **cache** `userId → name`.

### 4.2 Temps de jeu persistant (source de vérité)
- `PlayerDataService` gagne une clé numérique **`Playtime`** (persiste dans
  `PlayerData_v1`, miroir attribut, défaut **0**). Aucune montée de version : le merge des
  défauts donne `Playtime = 0` aux saves existantes (même pattern que `Rebirths`,
  cf. ARCHITECTURE §6.6).
- `LeaderboardService` note `joinTick` + `lastFlushTick` par joueur. À chaque flush (boucle
  périodique **et** `PlayerRemoving`) : `delta = now - lastFlush` →
  `PlayerDataService.add(player, "Playtime", delta)` → `lastFlush = now`, puis écriture de
  `Playtime` total dans `LB_Playtime_v1`.
- L'OrderedDataStore n'est qu'un **index** ; la source de vérité reste `PlayerData_v1`
  (bénéficie du garde « safe-save » existant : un échec de load n'écrase jamais la save).

## 5. Architecture & fichiers

Approche retenue : **serveur autoritaire + OrderedDataStore + rendu serveur** (réplication).
Colle aux conventions du projet (serveur autoritaire, remotes minimaux, fichiers à
responsabilité unique).

**Nouveaux fichiers**
- `src/shared/LeaderboardConfig.ts` — tunables + noms de stores + noms d'instances Studio
  (contrat partagé, comme `ButtonGameConfig` / `ShopBalance`).
- `src/server/services/LeaderboardService.ts` — orchestration : suivi join/leave,
  accumulation du temps, boucle de refresh, lecture/écriture OrderedDataStore, cache noms.
- `src/server/modules/LeaderboardBoard.ts` — rendu d'un panneau (remplit le ScrollingGui à
  partir des lignes classées). Présentation pure.
- `src/server/modules/PodiumDisplay.ts` — gère les 3 rigs : avatar (sur changement),
  nameplate, animation walk/idle.

**Fichiers modifiés**
- `src/server/services/index.ts` — enregistre `LeaderboardService` (après `PlayerDataService`
  / `PlayerProgressionService` : a besoin de l'attribut `Money` + des accesseurs PlayerData ;
  sa boucle est auto-pilotée donc la position tardive dans la liste est sans risque).
- `src/server/services/PlayerDataService.ts` — ajoute la clé `Playtime`.
- `src/shared/NumberFormat.ts` — ajoute `formatDuration(seconds)` → `"2j 5h"`, `"3h 12m"`,
  `"45m"` (réutilise le style de `FormatCash`).
- `ARCHITECTURE.md` — nouvelle §6.13 + maj §5 (ordre services), §6.6 (clé Playtime),
  §8 (tunables).

## 6. Boucle de rafraîchissement

Un seul `task.spawn` dans `LeaderboardService`, intervalle `REFRESH_INTERVAL` (défaut **60 s**) :

1. **Flush** — pour chaque joueur du serveur : accumule le temps écoulé, écrit `Money`
   courant dans `LB_Money_v1` et `Playtime` total dans `LB_Playtime_v1`. Chaque appel en
   `pcall`, **espacé** par un petit `task.wait` pour lisser les requêtes.
2. **Lecture** — `GetSortedAsync(false, TOP_N)` (1 page de 50) sur chaque store.
3. **Noms** — résout les UserId du top via le cache `GetNameFromUserIdAsync`.
4. **Rendu** — `LeaderboardBoard` (panneau argent), `LeaderboardBoard` (panneau temps),
   `PodiumDisplay` (top 3 du classement argent).

Flush supplémentaire sur `PlayerRemoving` (le départ met à jour le classement sans attendre
le prochain tick — important pour le temps de jeu). Toute la boucle est en `pcall` : en cas
d'échec DataStore, l'affichage **reste figé** (jamais de crash).

**Budget** : 1 lecture + N écritures par store / 60 s — très en deçà des limites
OrderedDataStore.

## 7. Panneaux physiques (défilement top 50, 15 visibles)

### 7.1 Structure Studio (créée par l'implémentation)
Sous `Workspace.Environment.LeaderBoards` :
```
MoneyBoard (Part, ancrée)
└── Display (SurfaceGui, Adornee = la part)
    ├── Header (TextLabel — titre)
    └── Rows (ScrollingFrame, AutomaticCanvasSize = Y, ScrollingDirection = Y)
        ├── UIListLayout
        └── Row1..Row50 (Frame : RankLabel · NameLabel · ValueLabel)
PlaytimeBoard (idem)
```
Placés de part et d'autre du podium (positions ajustables après coup).

### 7.2 Rendu (`LeaderboardBoard`)
- Les **50 lignes sont construites une seule fois** (lazy, puis mises en cache).
- À chaque refresh : **mise à jour du texte en place** ligne par ligne, lignes excédentaires
  **masquées** (`Visible = false`). On ne **détruit/recrée jamais** les lignes.
  → préserve la `CanvasPosition` (position de scroll) de **chaque** client et reste léger.
- Le scroll est **local au client** (propriété `CanvasPosition` côté client) : aucun
  RemoteEvent, chaque joueur défile indépendamment. La SurfaceGui posée dans le monde reçoit
  bien l'input molette / glissé tactile (PC **et** mobile).
- Hauteur dimensionnée pour ~**15 lignes visibles** ; le canvas s'étend jusqu'à 50.
- Formats : argent via `FormatCash` ; temps via `formatDuration`. État vide → lignes
  masquées / placeholder « — ».

## 8. Podium (top 3 argent)

### 8.1 Marches (existantes, déduites par hauteur/position)
| Marche | X | Sommet Y | Place |
|--------|----|---------|-------|
| Lapis (centre) | 0.5 | 8.06 (max) | 🥇 1er |
| Pink (droite) | 18.9 | 5.86 | 🥈 2e |
| Lime (gauche) | -17.8 | 3.37 | 🥉 3e |

Marches **ancrées** par l'implémentation (actuellement non ancrées).

### 8.2 Rigs
- Le `Rig` existant devient le **template** (`RigTemplate`, déplacé en `ServerStorage`).
  Son `Animate` (LocalScript inactif sur un NPC) et le script `Idle animation` sont
  **retirés** : les animations sont pilotées explicitement.
- 3 clones placés sur les 3 marches (pieds sur le sommet, orientés vers les spectateurs),
  dans un dossier `Podium`.

### 8.3 Rendu par refresh (`PodiumDisplay`), par place :
- **Avatar** : si l'occupant a **changé** depuis le dernier refresh →
  `ApplyDescription(GetHumanoidDescriptionFromUserId(userId))` en `pcall`
  (pattern de `CharacterService`). **Gated sur changement** : l'appel coûteux n'est pas
  rejoué toutes les 60 s.
- **Nameplate** : `BillboardGui` au-dessus de la tête → nom + montant (`FormatCash`).
- **Animation** : track chargé une fois par rig via l'`Animator`, joué en boucle —
  **1er = walk**, **2e & 3e = idle**. IDs d'animation dans `LeaderboardConfig`
  (défauts R15 standard, échangeables par ceux du rig).
- **Place vide** (moins de joueurs classés que de marches) : rig **masqué**, nameplate vidé.

## 9. Optimisations (exigences non-fonctionnelles)

- **Aucun hitch** (mobile inclus) : rendu serveur léger, avatars/noms **en cache**, appels
  DataStore espacés et en `pcall`.
- `ApplyDescription` **uniquement sur changement d'occupant** (le poste le plus coûteux).
- Lignes de panneau **réutilisées** (jamais recréées) → scroll préservé + coût minimal.
- **0 RemoteEvent / 0 script client** : tout réplique depuis le serveur (texte, avatars,
  animations).
- Boucle **robuste aux pannes** : tout en `pcall`, affichage figé plutôt que crash.

## 10. Mise à jour `ARCHITECTURE.md`

- **§6.13 Leaderboards & Podium** (nouveau) : data flow, stores, boucle, rendu serveur.
- **§5** : ajouter `LeaderboardService` à l'ordre de boot.
- **§6.6** : mentionner la clé `Playtime` de `PlayerDataService`.
- **§8** : ajouter `REFRESH_INTERVAL`, `TOP_N`, `VISIBLE_ROWS`.

## 11. Tunables (`shared/LeaderboardConfig.ts`)

| Constante | Défaut | Sens |
|-----------|--------|------|
| `REFRESH_INTERVAL` | 60 s | Période de la boucle refresh |
| `TOP_N` | 50 | Entrées lues/stockées par classement |
| `VISIBLE_ROWS` | 15 | Lignes visibles avant défilement |
| `MONEY_STORE` / `PLAYTIME_STORE` | `LB_Money_v1` / `LB_Playtime_v1` | Noms OrderedDataStore |
| `WALK_ANIM_ID` / `IDLE_ANIM_ID` | (R15 standard) | Animations podium |
| `WRITE_SPACING` | ~0.1 s | Espacement entre écritures DataStore |

## 12. Critères d'acceptation

1. Les 2 panneaux affichent le **top 50**, **15 visibles**, **défilables** (PC + mobile),
   scroll **préservé** à travers les refresh.
2. Podium : top 3 par argent, **avatars réels**, **1er marche**, **2e/3e idle**.
3. Le **temps de jeu persiste** et s'accumule entre sessions ; le classement **argent** =
   `Money` courant (redescend après rebirth).
4. Refresh ~60 s ; **aucun hitch** ; **aucun RemoteEvent**.
5. États partiels gérés (< 3 joueurs classés, store vide).
6. `npm run build` passe ; ARCHITECTURE.md à jour.
