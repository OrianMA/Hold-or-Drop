# Rééquilibrage progression & rebirth — Design

Date : 2026-07-22

## Problèmes constatés

1. Les premières améliorations ne se voient pas.
2. Dans les premières minutes les joueurs ne comprennent pas qu'il faut **claim**.
3. Les premiers niveaux de **Resistance** sont quasi inutiles.
4. Idem pour la **vitesse**.
5. Le **rebirth** n'est pas assez rentable, et on met trop longtemps à revenir à son niveau.

## Diagnostic chiffré

Mesuré par simulation de l'économie actuelle (joueur qui claim au temps optimal en
espérance et achète l'upgrade au meilleur gain/$) :

| Mesure | Valeur actuelle |
|---|---|
| Re-climb après rebirth (cycle R1) | **11 runs sur 12** passés à racheter l'existant |
| Resistance L1 (500$) | survie médiane **7,5 s → 7,5 s** (zéro effet) |
| Resistance L5 (6 593$ cumulés) | 7,5 s → **8,5 s** |
| Resistance L30 pour atteindre 30 s | **191 000 000 $** |
| Multiplicateur au run #1 | claim optimal à **2 s**, ×1,03 |
| Taux de survie au claim optimal | **56-64 %** (4 runs perdus sur 10) |

### Hypothèses du modèle

Les chiffres viennent d'un simulateur (`tools/economy-sim.js`, §7) qui modélise :

- un joueur qui **claim au temps maximisant l'espérance** de gain, et achète à chaque
  retour au shop l'upgrade au meilleur gain de revenu par dollar ;
- un **overhead de 18 s par run** (explosion, animation de paiement, retour au bouton),
  auquel s'ajoute le temps de vol → cycle complet de 23 s (début de partie) à 34 s (fin).

Un vrai joueur claim moins bien et répartit moins bien ses achats : les durées de cycle
réelles seront **un peu plus longues** que celles indiquées. Les grandeurs relatives
(re-climb, valeur d'un niveau, ratios entre stats) restent valides.

### Trois causes racines

**(a) `riskScale` agit en racine cubique.** La survie médiane vaut
`≈ 7,2 · riskScale^(−1/3)`. Il faut **diviser le risque par 8** pour doubler la durée de
vol. Aucun réglage ne rendra ce levier lisible. La `safeWindow` est linéaire — mais elle est
aujourd'hui *back-loaded* (0,0 s jusqu'au niveau 15), donc inexistante dans la plage
réellement achetée (L0..L15).

**(b) Le rebirth donne moins qu'il ne retire.** Au rebirth le revenu chute de
16 726$ → 473$ (**÷35**) : on perd les niveaux BaseCash (÷7), RocketSpeed (÷7 sur le
multiplicateur) et Resistance (vol de 14 s → 5 s), pour ne regagner que **×2**.
Formule : re-climb ≈ `(runs pour atteindre le mur) / (ratio du multiplicateur)`. Avec un
ratio ×2 le re-climb occupe mathématiquement la moitié du cycle.

**(c) La fusée rampe au niveau 0.** `ROCKET_ACCEL = 1`, `ROCKET_MAX_SPEED = 10` : en 10 s de
vol le multiplicateur atteint ×1,55. Le nombre ne bouge pas → aucun signal
« tenir/claim rapporte », d'où le problème 2.

## Cible

- **Boucle de rebirth : 5-8 min** (~12-16 runs à ~28 s le cycle complet).
- **Retour au niveau précédent en ~3 runs**, puis 4-6 runs en territoire neuf, puis
  stagnation courte avant le rebirth suivant.
- Un achat possible dès le **premier run**.

## Périmètre

Chiffres + UI/feedback + onboarding du claim. **Pas de nouveau système de progression**
(pas de paliers gratuits, pas d'achat x10, pas de plancher de stats post-rebirth).

---

## 1. Le run — `shared/RocketGameConfig.ts`

Les constantes sont **par unité de RocketSpeed** (`launch()` les multiplie par la stat).

| Constante | Avant | Après |
|---|---|---|
| `ROCKET_ACCEL` | 1 | **3** |
| `ROCKET_MAX_SPEED` | 10 | **30** |
| `MULTIPLIER_PER_STUD` | 0.01 | inchangé |
| `RISK_RAMP_DURATION` | 17 | inchangé |

`ROCKET_SPEED.baseValue` **reste à 1** : c'est ce qui rend le premier achat de vitesse
maximal (+100 % vitesse *et* multiplicateur), puis dégressif — le « drastique au début,
faible ensuite » demandé.

Multiplicateur obtenu (vitesse plafonnée à 10 s de vol, puis croissance linéaire) :

| RocketSpeed | valeur | 5 s | 10 s | 14 s | 20 s |
|---|---|---|---|---|---|
| 0 (départ) | 1 | ×1.5 | ×2.6 | ×3.8 | ×5.6 |
| 1 | 2 | ×1.9 | ×4.3 | ×6.7 | ×10.3 |
| 2 | 3 | ×2.4 | ×6.0 | ×9.6 | ×15.0 |
| 5 | 6 | ×3.7 | ×10.9 | ×18.1 | ×28.9 |
| 10 | 11 | ×6.0 | ×19.2 | ×32.4 | ×52.1 |
| 20 | 21 | ×10.4 | ×35.6 | ×60.8 | ×98.6 |

Effet sur l'onboarding : le claim optimal passe de **2 s à 5 s** au tout premier run — le
joueur a le temps de voir le nombre monter avant la première explosion.

## 2. Resistance — de « −X % de risque » à « X secondes garanties »

Changement le plus structurant. La `safeWindow` devient le levier principal et passe en
**front-loaded** ; `riskScale` devient secondaire.

### Déplacement en shared (prérequis)

Les constantes et `resistanceRiskParams` vivent aujourd'hui dans
`server/modules/ButtonInGameModule.ts`. Le client doit calculer la même fenêtre pour
l'afficher dans le shop → **déplacer dans `shared/ResistanceCurve.ts`**, importé par le
serveur (boucle de risque) et le client (affichage). Même pattern que `RocketGameConfig`.

### Formule

```
n          = clamp(resistance / 100, 0, 1)
riskScale  = 1 − MAX_REDUCTION × (1 − (1 − n)^REDUCTION_CURVE)
safeWindow = MAX_SAFE_WINDOW × (1 − (1 − n)^SAFE_WINDOW_CURVE)   // ← inversé
```

La seule modification de forme est `safeWindow` : `n^C × MAX` (back-loaded) devient
`MAX × (1 − (1−n)^C)` (front-loaded), soit exactement la forme déjà utilisée par
`riskScale`. `riskAt()` et `rollExplosionTime()` sont inchangés.

| Constante | Avant | Après |
|---|---|---|
| `RESISTANCE_MAX_SAFE_WINDOW` | 15 | **8** |
| `RESISTANCE_SAFE_WINDOW_CURVE` | 2.5 (back-loaded) | **14 (front-loaded)** |
| `RESISTANCE_MAX_REDUCTION` | 0.99 | **0.75** |
| `RESISTANCE_REDUCTION_CURVE` | 12 | **13** |
| `RESISTANCE_MAX_LEVEL` | 100 | inchangé |

### Ce que chaque niveau achète

| Niveau | Prix du niveau | Cumulé | Fenêtre garantie | Survie médiane | Δ vs niveau précédent |
|---|---|---|---|---|---|
| 0 | — | — | 0,0 s | 7,0 s | — |
| **1** | **150$** | 150$ | **1,1 s** | **8,5 s** | **+1,5 s** |
| 2 | 202$ | 352$ | 2,0 s | 9,5 s | +1,0 s |
| 3 | 273$ | 625$ | 2,8 s | 10,5 s | +1,0 s |
| 4 | 369$ | 994$ | 3,5 s | 11,5 s | +1,0 s |
| 5 | 498$ | 1 492$ | 4,1 s | 12,5 s | +1,0 s |
| 8 | 1 225$ | 4 297$ | 5,5 s | 14,5 s | +0,5 s |
| 10 | 2 234$ | 8 185$ | 6,2 s | 15,5 s | +0,5 s |
| 15 | 10 017$ | 38 204$ | 7,2 s | 17,5 s | +0,5 s |
| 20 | 44 919$ | 172 823$ | 7,6 s | 18,5 s | +0,0 s |
| 30 | 903 172$ | 3,5 M$ | 7,9 s | 19,0 s | **+0,0 s** |

La stat sature naturellement vers le niveau 25-30 : `maxLevel: 100` reste inchangé et le
bouton n'affiche jamais « MAX » de façon prématurée.

### Game pass Resistance

`RESISTANCE_PASS.addLevels = 20` devient beaucoup plus fort avec une courbe front-loaded
(+20 niveaux depuis 0 ≈ 7,6 s garanties, quasi le plafond). Le pass est **inerte**
(`gamePassId: 0`) tant qu'il n'est pas créé sur le dashboard — à re-calibrer (suggestion :
`addLevels: 8`) avant publication. Hors périmètre de ce lot.

## 3. Prix par stat — `shared/ShopBalance.ts` / `shared/ShopConfig.ts`

Les trois stats se **multiplient** entre elles (revenu = `BaseCash × mult(vitesse, temps de
vol)`, et la Resistance rallonge le temps de vol). Avec un `PRICE_GROWTH` global unique
l'économie s'emballe — mesuré : 2 à 6 runs par cycle. Il faut un mur par stat.

**Changement de structure minimal** : ajouter un champ `priceGrowth` à chaque bloc de
`ShopBalance`, lu par `StatConfig`. `PRICE_GROWTH` reste exporté comme valeur par défaut.
`priceForLevel` devient `floor(startPrice × STATS[stat].priceGrowth ^ level)`.

| Stat | startPrice | priceGrowth | Rôle |
|---|---|---|---|
| BaseCash | 25 → **50** | 1.5 → **1.8** | mur raide — stat d'argent pur |
| RocketSpeed | 100 → **75** | 1.5 → **1.7** | mur raide |
| Resistance | 500 → **150** | 1.5 → **1.35** | mur doux, beaucoup de petits paliers |

`BASE_CASH.baseValue` (100) et `valueGrowth` (1.2) restent inchangés.

Le premier run rapporte **118$**, donc un achat est possible dès le retour au shop :

| Premier achat | Prix | Revenu/run | Gain | Vol |
|---|---|---|---|---|
| départ (BC0 RS0 RE0) | — | 118$ | — | 5 s, survie 76 % |
| BaseCash L1 | 50$ | 142$ | +20 % | 5 s |
| RocketSpeed L1 | 75$ | 154$ | **+30 %** | 6 s |
| Resistance L1 | 150$ | 134$ | +13 % | **6 s, survie 78 %** |

## 4. Rebirth

### 4.1 Modèle de multiplicateur : rebirth multiplicatif, boosts additifs

`ShopConfig.moneyMult` passe de additif pur à :

```
moneyMult = MultRebirth × (1 + (inCommunity ? COMMUNITY.mult − 1 : 0) + (moneyTierMult − 1))
```

**Raison** : le re-climb rapide exige un ratio de rebirth élevé (×8). En additif, un
`MultRebirth` de 4 096 écraserait totalement les 10 paliers `MONEY_TIERS` (×2…×1024) —
un pass ×2 n'ajouterait plus que +1 sur 4 096, rendant la monétisation invendable. En
multiplicatif, **un pass ×2 reste ×2 quel que soit le rebirth**, à vie.

Le readout `ShopMenu/Header/MultiplierText` doit refléter la nouvelle décomposition
(`MultRebirth` × facteur de boosts) au lieu d'une somme.

### 4.2 Récompense et coût

| Élément | Avant | Après |
|---|---|---|
| `rebirthMult(R)` | table `[1,2,3,3.5,4,4.5,4.75,5]` puis `+0.25` | **`REBIRTH.multGrowth ^ R`, `multGrowth = 8`** |
| `rebirthCost(R)` | `2 500 × 2.4^R` | **`20 000 × 30^R`** |

`REBIRTH.multTable` et `multTail` sont supprimés au profit de `multGrowth`.

### 4.3 Résultat simulé

| R | runs | min | **runs pour retrouver le pic précédent** | BC / RS / RE atteints | coût du rebirth |
|---|---|---|---|---|---|
| 0 | 20 | 9,5 | — | 10 / 11 / 14 | 20 000 |
| 1 | 9 | 4,5 | **3** | 16 / 15 / 20 | 600 000 |
| 2 | 7 | 3,6 | **3** | 22 / 20 / 30 | 18 M |
| 3 | 7 | 3,7 | **3** | 28 / 28 / 39 | 540 M |
| 4 | 7 | 3,8 | **3** | 33 / 35 / 53 | 16,2 G |
| 5 | 8 | 4,3 | **3** | 40 / 40 / 65 | 486 G |
| 6 | 12 | 6,6 | **3** | 45 / 49 / 84 | 14,6 T |
| 7 | 13 | 7,2 | **3** | 51 / 56 / 94 | 437 T |

R0 (9,5 min) est le cycle d'apprentissage : le premier rebirth se mérite. À partir de R1
la boucle tient dans 3,6-7,2 min et s'allonge naturellement.

### 4.4 Forme du cycle R1 — la boucle visée

| Run | Revenu | Phase |
|---|---|---|
| 1 | 947$ | rebirth, on repart de zéro |
| 2 | 4 080$ | **re-climb explosif** (×4,3 en un run) |
| 3 | **19 324$** | dépasse le pic du cycle précédent (16 726$) |
| 4 | 59 995$ | territoire neuf |
| 5 | 142 671$ | territoire neuf |
| 6 | 249 734$ | territoire neuf |
| 7 | 357 095$ | ralentissement |
| 8 | 464 918$ | **stagnation** — on épargne |
| 9 | 594 253$ | rebirth |

Croissance par run : ×4,3 → ×4,7 → ×3,1 → ×2,4 → ×1,8 → ×1,4 → ×1,3 → ×1,3. La
décélération produit d'elle-même la phase de stagnation qui donne envie de rebirth.

### 4.5 Risques identifiés

- **Safe rebirth payant** (`RebirthService.safeRebirth` : garde argent + niveaux, +1
  rebirth) devient très puissant — ×8 instantané sans reset. Bon pour le revenu,
  potentiellement cassé. À arbitrer séparément ; **non modifié dans ce lot**.
- **Joueurs déjà rebirthés massivement buffés** : un joueur R5 passe de ×4,5 à ×32 768.
  Acceptable en phase de développement ; aucune migration de sauvegarde n'est nécessaire
  (les niveaux et `Rebirths` sont stockés, les valeurs sont dérivées).
- **Précision numérique** : au-delà de ~9×10¹⁵ (2⁵³) l'argent devient approximatif. Sans
  impact pratique — gains et prix croissent ensemble, et l'affichage est toujours formaté.
  `FormatNumber` couvre jusqu'à 10⁶³ (`Vg`), largement suffisant.

## 5. UI — montrer l'impact, pas le nombre brut

`client/behaviors/ShopItemsController.ts` + `StatConfig.display` dans `ShopConfig`.

`display` reçoit un contexte (`{ moneyMult }`) pour pouvoir rendre la valeur effective.

| Bouton | Aujourd'hui | Proposé |
|---|---|---|
| BaseCash | `1K → 1.2K` (valeur brute) | **`512K → 614K`** — `EffectiveBaseCash`, multiplicateur de rebirth inclus |
| RocketSpeed | `3 → 4` | `3 → 4`, plus **`×6.0 → ×7.6` à 10 s de vol** |
| Resistance | `3 → 4` | **`2,6 s → 3,3 s garanties`** |

La Resistance en **secondes** est la correction de lisibilité clé : « Resistance 3 → 4 » ne
veut rien dire, « 2,6 s → 3,3 s garanties » se comprend immédiatement. C'est aussi ce qui
rend la stat vendable, puisque son effet réel est désormais une durée.

Le rendu Resistance et RocketSpeed a besoin de `shared/ResistanceCurve.ts` (§2) et de
`RocketGameConfig` — tous deux shared, donc client et serveur affichent la même chose.

## 6. Onboarding du claim

`client/behaviors/RocketLaunchBehavior.ts` : le `ClaimButton` **pulse** (tween de `Size`
en boucle + halo) tant que le joueur n'a pas claim **3 fois dans la session**. Compteur en
mémoire côté client, aucun état serveur, aucun champ DataStore, aucun événement réseau.

Le pulse s'arrête dès le claim en cours (le bouton devient rouge/non-cliquable) et reprend
au lancement suivant tant que le compteur est sous 3.

Combiné au §1 (claim optimal repoussé de 2 s à 5 s), le joueur a le temps de voir le bouton
pulser et le multiplicateur monter avant la première explosion.

## 7. Fichiers touchés

| Fichier | Nature |
|---|---|
| `shared/RocketGameConfig.ts` | 2 constantes |
| `shared/ResistanceCurve.ts` | **nouveau** — constantes + `resistanceRiskParams`, déplacés depuis `ButtonInGameModule` |
| `server/modules/ButtonInGameModule.ts` | supprime les constantes/fonction, importe depuis shared |
| `shared/ShopBalance.ts` | prix de départ, `priceGrowth` par stat, bloc `REBIRTH` |
| `shared/ShopConfig.ts` | `priceForLevel` par stat, `moneyMult` multiplicatif, `rebirthMult` géométrique, `display` avec contexte |
| `client/behaviors/ShopItemsController.ts` | rendu de l'impact réel |
| `client/behaviors/BoostShopController.ts` | readout du multiplicateur (décomposition multiplicative) |
| `client/behaviors/RocketLaunchBehavior.ts` | pulse du `ClaimButton` |
| `ARCHITECTURE.md` | §6.3, §6.6, §6.8, §6.9 |
| `tools/economy-sim.js` | **nouveau** — simulateur ayant produit ces chiffres, à committer pour les futurs réglages |

Aucune migration DataStore : les niveaux et `Rebirths` sont la source de vérité persistée,
toutes les valeurs sont dérivées.

## 8. Vérification

Critères mesurables, à valider par le simulateur (`tools/economy-sim.js`) **et** en jeu :

1. Le premier run rapporte ≥ 100$ et permet un achat immédiat.
2. Resistance L1 : fenêtre garantie ≥ 1,0 s et survie médiane ≥ 8,0 s (contre 7,5 s à L0).
3. RocketSpeed L0→L1 : multiplicateur à 10 s de vol ≥ ×4,0 (contre ×2,6).
4. Cycles R1..R7 entre 3,5 et 8 min.
5. Runs pour retrouver le pic de revenu précédent après rebirth : **≤ 3** pour R1..R7.
6. Un pass money ×2 multiplie bien le revenu par 2 à n'importe quel niveau de rebirth.
7. En jeu : le shop affiche des secondes pour Resistance et l'`EffectiveBaseCash` pour
   BaseCash ; le `ClaimButton` pulse au premier lancement et s'arrête après 3 claims.
