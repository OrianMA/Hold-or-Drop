# Spec — Progression Rebirth & courbes d'upgrade corrigées

> Date : 2026-06-10
> Statut : design validé, en attente de plan d'implémentation
> Jeu : Hold or Drop (Roblox-TS). Voir `ARCHITECTURE.md`.

## 1. Contexte & objectif

Refondre la progression argent/améliorations pour suivre les patterns éprouvés des
jeux incrémentaux et des Roblox « cash-grab » :

- **Early game fort et visuel** : les premières améliorations claquent (gros effet, pas cher).
- **Ralentissement naturel** ensuite, sans mur brutal.
- **Une couche Rebirth** qui relance la boucle de plus en plus fort, **sans inflation
  illisible** des nombres (pas de « 10 chiffres → 11 chiffres en une upgrade »).

La garantie « pas d'infini illisible » vient du **reset total au rebirth** : les nombres
visibles (cash par manche, prix des upgrades) repartent bas à chaque cycle ; seul un petit
multiplicateur permanent `×N` persiste et grandit doucement.

## 2. Diagnostic du système actuel (à corriger)

Dans `shared/ShopBalance.ts`, le **BaseCash est mathématiquement cassé** : la valeur croît
plus vite que le prix → chaque niveau est *plus rentable* que le précédent → emballement
infini.

| Stat | Valeur croît à | Prix croît à | Verdict |
|------|----------------|--------------|---------|
| BaseCash | ×1.8 / niveau | ×1.5 / niveau | ❌ valeur > prix → emballement |
| Multiplier | ×1.3 / niveau | ×1.5 / niveau | ✅ sain |
| Safety | +5% linéaire (cap 10) | ×1.5 / niveau | ✅ borné |

**Règle d'or** (recherche sur les jeux incrémentaux) : *le prix doit toujours croître plus
vite que la valeur*. C'est ce qui crée le ralentissement et empêche l'explosion.

## 3. Comment marchent les améliorations (rappel pédagogique)

Gain d'une manche :

```
gain = floor( BaseCash × multiplicateurDeManche × MultRebirth )
```

- **BaseCash** — point de départ de la manche (niveau 0 = 100). Chaque achat = +20%.
  Plus il est haut, plus chaque manche rapporte, indépendamment du temps tenu.
- **Multiplier** — pendant le hold, un multiplicateur monte chaque seconde. Cette stat
  donne le **gain par seconde** (niveau 0 = +0.1/s). Départ à ×1 ; après *t* secondes :
  `multiplicateurDeManche = 1 + Multiplier × t`. (La boucle existe déjà — inchangée.)
- **Safety** — réduit le risque d'explosion (+5%/niveau, cap 50%).
- **MultRebirth** — multiplicateur permanent gagné via les rebirths (section 5). Multiplie
  *tout* le gain. C'est la seule nouvelle entrée dans la formule.

Exemples chiffrés (avec les courbes corrigées, MultRebirth = 1) :

| Situation | Calcul | Gain |
|-----------|--------|------|
| L0, hold 10s | 100 × (1 + 0.1×10) | 200 |
| L0, hold ~17s (limite) | 100 × 2.7 | 270 |
| BaseCash L5, Multiplier L5, hold 10s | 249 × (1 + 0.23×10) | ≈ 821 |

Avec un MultRebirth ×3, le même dernier exemple rapporte ≈ 2 463.

## 4. Courbes d'upgrade corrigées

On garde la mécanique existante (`shared/ShopConfig.ts` dérive valeur et prix depuis les
niveaux ; `PRICE_GROWTH` global). On **ne change que les nombres** dans `shared/ShopBalance.ts`.

Valeurs de départ proposées (toutes ajustables, voir §11) :

```
PRICE_GROWTH = 1.5            // global, inchangé. Prix(niv) = startPrice × 1.5^niv

BASE_CASH   = { baseValue: 100, valueGrowth: 1.20, startPrice: 25  }
MULTIPLIER  = { baseValue: 0.1, valueGrowth: 1.18, startPrice: 100 }
SAFETY      = { perLevel: 0.05, maxLevel: 10,      startPrice: 500 }  // baissé de 2000
```

Invariant à respecter : **`valueGrowth < PRICE_GROWTH`** pour BaseCash et Multiplier.

- BaseCash : `valeur = 100 × 1.20^niv`, `prix = 25 × 1.5^niv`.
- Multiplier : `valeur = 0.1 × 1.18^niv`, `prix = 100 × 1.5^niv`.
- Safety : inchangée dans la forme (linéaire capée), juste `startPrice` baissé car elle se
  reset à chaque cycle de rebirth.

## 5. Système de Rebirth

### 5.1 Sémantique du reset

Au rebirth, on **reset tout** :

- `Money` → 0 (via `PlayerDataService`).
- `BaseCashLevel`, `MultiplierLevel`, `SafetyLevel` → 0 (donc les valeurs dérivées
  reviennent à leur défaut niveau 0).
- `Rebirths` → +1.

Le seul état qui persiste et grandit est `Rebirths` (et la valeur dérivée `MultRebirth`).

### 5.2 Condition (coût)

```
coûtRebirth(R) = floor( REBIRTH_BASE_COST × REBIRTH_COST_GROWTH ^ R )
REBIRTH_BASE_COST   = 2500
REBIRTH_COST_GROWTH = 2.4
```

`R` = nombre de rebirths déjà faits. Le 1er rebirth coûte 2 500 ; chaque suivant ×2.4.
La croissance est volontairement plus douce qu'une exponentielle agressive pour que les
rebirths restent **toujours atteignables** malgré le taper de la récompense. Réglage final
par simulation (cible : 1er rebirth en ~3-5 min de jeu actif).

### 5.3 Récompense (MultRebirth) — table + queue

Multiplicateur permanent, **table de valeurs** pour le début (contrôle exact du « début
puissant »), puis **queue linéaire** constante :

```
REBIRTH_MULT_TABLE = [1, 2, 3, 3.5, 4, 4.5, 4.75, 5]   // index = R (R=0 → 1)
REBIRTH_MULT_TAIL  = 0.25                                // par rebirth au-delà de la table

multRebirth(R):
    if R < len(REBIRTH_MULT_TABLE): return REBIRTH_MULT_TABLE[R]
    else: return REBIRTH_MULT_TABLE[last] + (R - lastIndex) × REBIRTH_MULT_TAIL
```

| R | MultRebirth | Gain |
|---|-------------|------|
| 1 | ×2.0  | +1.0 |
| 2 | ×3.0  | +1.0 |
| 3 | ×3.5  | +0.5 |
| 4 | ×4.0  | +0.5 |
| 5 | ×4.5  | +0.5 |
| 6 | ×4.75 | +0.25 |
| 7 | ×5.0  | +0.25 |
| 8+ | +0.25 / rebirth | queue |

Gros gains au début, puis hausse régulière qui **ne s'arrête jamais** mais reste un petit
nombre lisible (×6 vers R12, ×8 vers R20). Toutes ces valeurs vivent dans `ShopBalance.ts`.

## 6. Formule de paiement & flux d'animation

### 6.1 Serveur — `modules/ButtonInGameModule.ts`

Lire `MultRebirth` une fois au début de la session (comme BaseCash / Multiplier / Safety
sont déjà lus une fois). Appliquer sur les deux fins :

- Release / explosion survécue : `earned = floor(baseCash × currentMultiplier × multRebirth)`.
- Mort : `earned = floor(baseCash × LOOSE_WIN_MULTIPLIER × currentMultiplier × multRebirth)`.

Le serveur reste la **source de vérité** du montant crédité (crédité après l'animation, cf.
`ARCHITECTURE.md` §6.4).

### 6.2 Client — animation de fin

`runEndGameAnimation(...)` (`client/ui/EndGameAnimation.ts`) calcule actuellement
`totalEarn = effectiveBaseCash × multiplier`. Il doit afficher le **même** total que celui
crédité → lui transmettre `multRebirth` :

- `EndGameStartEvent` : ajouter un paramètre `multRebirth` (S→C).
- `runEndGameAnimation` : nouveau paramètre `multRebirth`, `totalEarn = effectiveBaseCash ×
  multiplier × multRebirth`.

`GameResultEvent` transporte déjà le `earned` final calculé serveur → reste correct.

## 7. Modèle de données / persistance

`PlayerProgressionService` (store `PlayerProgression_v2`) suit le pattern « niveaux
persistés, valeurs dérivées ». On ajoute une dimension :

- Nouveau champ persisté : `Rebirths` (entier, défaut 0).
- Nouvel attribut dérivé : `MultRebirth` (mirroré pour réplication client + lecture par la
  boucle de jeu).
- **Pas de bump de version** : le merge de chargement applique déjà des défauts pour les
  champs manquants, donc les saves existants prennent `Rebirths = 0` sans migration.

Nouvelles méthodes sur `PlayerProgressionService` :

- `getRebirths(player): number`
- `getMultRebirth(player): number` (lit l'attribut dérivé)
- `rebirth(player): void` — réinitialise les 3 niveaux de stat à 0, incrémente `Rebirths`,
  re-dérive `MultRebirth` et les 3 valeurs. (Ne touche pas `Money` — c'est l'appelant qui
  remet `Money` à 0 via `PlayerDataService`, pour garder chaque service responsable de son
  store.)

## 8. Réseau — events (`shared/Event.ts`)

- **Nouveau** `RebirthEvent` (C→S) : le joueur clique « Rebirth ». Pas d'argument.
- **Modifié** `EndGameStartEvent` (S→C) : ajoute `multRebirth` à la charge utile.

Pas d'event de réponse pour le rebirth : le client lit les attributs mis à jour (`Money`,
les 3 niveaux, `Rebirths`, `MultRebirth`) par réplication. En cas de refus (cash < coût),
flasher `InformationTextEvent` (« Pas assez d'argent »).

## 9. Côté serveur — handler de rebirth

Nouveau `server/services/RebirthService.ts` (responsabilité unique : valider + exécuter un
rebirth). Sur `RebirthEvent` :

1. Lire `Money` et `Rebirths` du joueur.
2. Calculer `coûtRebirth(Rebirths)` (helper depuis `ShopConfig`).
3. Si `Money < coût` → `InformationTextEvent`, stop.
4. Sinon : `PlayerDataService.set(player, "Money", 0)` puis
   `PlayerProgressionService.rebirth(player)`.

Boot order (`services/index.ts`) : **après `ShopService`** (a juste besoin de PlayerData +
PlayerProgression prêts, déjà bootés avant ShopService). Documenter l'ajout dans `index.ts`
et `ARCHITECTURE.md`.

Helpers à ajouter dans `shared/ShopConfig.ts` (purs, partagés client/serveur) :

- `rebirthCost(rebirths: number): number`
- `rebirthMult(rebirths: number): number`

## 10. UI client + Studio

- **HUD** : afficher le multiplicateur courant (`×N`) et éventuellement le compteur de
  rebirths. Lecture pure depuis les attributs répliqués `MultRebirth` / `Rebirths`.
- **Panneau Rebirth** : dans le `ShopMenu` existant (cohérent avec les 4 boutons d'upgrade),
  un bloc montrant `MultRebirth` actuel → suivant, le coût, et un bouton « Rebirth » grisé
  si `Money < coût`. Même pattern de rafraîchissement que `ShopItemsController` (refresh
  depuis les attributs, aucun event de réponse).
- **Controller** : nouveau `client/behaviors/RebirthController.ts` (ou extension de
  `ShopItemsController`) qui binde le bouton, rend les valeurs et fire `RebirthEvent`.
- **Studio** : le `.rbxl` n'est pas versionné → les frames GUI du panneau Rebirth doivent
  être créées dans Studio (inspecter `MainUI/ShopMenu/Body` et y ajouter le frame Rebirth).
  À faire via le MCP Roblox_Studio pendant l'implémentation ; reporter ce qui est créé.

## 11. Réglages à valider par simulation

Tous les nombres ci-dessous sont des **points de départ**, à affiner en simulant la
progression (script de simulation hors-jeu) pour viser le rythme « 1er rebirth ~3-5 min,
puis qui s'espace » :

- `valueGrowth` BaseCash (1.20) / Multiplier (1.18), `PRICE_GROWTH` (1.5), `startPrice`.
- `REBIRTH_BASE_COST` (2500), `REBIRTH_COST_GROWTH` (2.4).
- `REBIRTH_MULT_TABLE` / `REBIRTH_MULT_TAIL`.

Vérifications de cohérence : (a) `valueGrowth < PRICE_GROWTH` ; (b) chaque rebirth reste
atteignable (coût croît, mais le pouvoir d'achat par cycle croît aussi via le MultRebirth +
les niveaux plus hauts atteignables) ; (c) les nombres affichés restent lisibles
(formatés par `NumberFormat`).

## 12. Hors scope

- **Robux / monétisation** : les boutons Robux ne sont pas câblés ; non traités ici. Hooks
  naturels futurs : rebirth instantané, gamepass ×2 cash.
- Refonte de la boucle hold/risk : **inchangée** (seul le payout final est multiplié).
- Nouvelles zones / boutons à débloquer : non retenu pour cette itération.

## 13. Critères d'acceptation

1. BaseCash respecte `valueGrowth < PRICE_GROWTH` (plus d'emballement).
2. Le gain d'une manche = `floor(BaseCash × multiplicateurDeManche × MultRebirth)`, sur win
   comme sur mort (avec `LOOSE_WIN_MULTIPLIER`).
3. Le rebirth : refuse si `Money < coûtRebirth(Rebirths)` ; sinon reset Money + 3 niveaux,
   `Rebirths += 1`, `MultRebirth` re-dérivé selon la table/queue.
4. `MultRebirth` persiste entre sessions ; les saves existants chargent avec `Rebirths = 0`
   sans migration.
5. L'animation de fin affiche exactement le montant crédité (transmission de `multRebirth`).
6. Le HUD et le panneau Rebirth se rafraîchissent depuis les attributs répliqués (pas
   d'event de réponse), bouton grisé si non finançable.
7. `ARCHITECTURE.md` mis à jour (event catalog, boot order, persistance, formule de payout).
