# Spec — Multiplicateurs d'argent appliqués au Base Cash

> Date : 2026-06-24
> Statut : design validé, en attente de plan d'implémentation
> Branche : `feat/money-mult-basecash`
> Jeu : Hold or Drop (Roblox-TS). Voir `ARCHITECTURE.md`.
> Antécédent : `2026-06-10-rebirth-progression-design.md` (qui a introduit le `MultRebirth`
> appliqué au paiement — c'est précisément ce que ce spec déplace).

## 1. Contexte & objectif

Aujourd'hui le multiplicateur de rebirth (`MultRebirth`) est appliqué **à la fin de la
manche**, sur le paiement : `floor(BaseCash × multiplicateurDeManche × MultRebirth)`
(cf. `ARCHITECTURE.md` §6.3).

On veut **le déplacer en amont, sur le Base Cash lui-même**, pour qu'il soit visible en
permanence sur le bouton et qu'il « gonfle » la base affichée. Et on généralise : le Base
Cash sera multiplié par **3 facteurs indépendants** qui se cumulent, tous vérifiables côté
serveur :

1. **Rebirth** — le `MultRebirth` existant (table inchangée).
2. **Game pass argent** — échelle de paliers (×2 … ×1024), **le palier le plus haut possédé
   gagne**.
3. **Communauté** — ×2 si le joueur est membre du **groupe Roblox `963505568`**.

Plus un **game pass safety** distinct : **+20 %** de réduction de risque, ajouté à la
`AdditionalSecurity` du shop.

**Comportement cible (exemple)** : Base brut 100, rebirth ×2 → le bouton affiche **200**.
Le joueur monte son Base à 150 → **300**. S'il a en plus la communauté ×2 → total ×3 (bonus
additifs, cf. §1.1) → 150 affiche **450**.

### 1.1 Décisions actées (brainstorming)

- **Combinaison des 10 game pass argent** : *paliers, le plus haut gagne* (×2,×4,…,×1024 ;
  on possède le palier le plus élevé acheté ; un palier supérieur remplace). Max ×1024.
- **Combinaison des facteurs** (rebirth + palier + communauté) : *bonus additifs* — chaque
  « ×N » ajoute « +(N−1) » ; total `= 1 + Σ(mᵢ−1)`. Un boost seul vaut sa valeur ; joueur
  neuf = ×1. (Ex. rebirth ×2 + communauté ×2 + palier ×4 → ×6, pas ×16.) Tout futur
  multiplicateur indépendant s'ajoute pareil.
- **Communauté** : *groupe Roblox `963505568`* (`player:IsInGroup`), vérifié serveur.
- **Animation de paiement** : *retirer la phase or « xN rebirth »* (le boost est désormais
  déjà dans la base de départ).
- **Plafond safety cumulé** : *70 %* (shop 50 % + pass 20 %), risque plancher ×0.30.
- **Portée shop maintenant** : *readout du multiplicateur + bouton communauté (live) +
  boutons safety-pass et palier-suivant (inertes jusqu'aux IDs)*.
- **IDs game pass** : inconnus pour l'instant → mis en config à `0` = **inertes** (pattern
  « id vide = no-op », comme les anim ids). Le groupe communauté est live tout de suite.

## 2. Modèle & formules

```
// Bonus additifs : chaque « ×N » contribue « +(N-1) ». MultRebirth (≥1) porte la base 1.
MoneyMult         = MultRebirth + (InCommunity ? COMMUNITY.mult-1 : 0) + (MoneyTierMult-1)
                  = 1 + (MultRebirth-1) + communityBonus + tierBonus
EffectiveBaseCash = floor( BaseCash_brut × MoneyMult )

paiement (win/parry/grace) = floor( EffectiveBaseCash × currentMultiplier )
paiement (mort)            = floor( EffectiveBaseCash × LOOSE_WIN_MULTIPLIER × currentMultiplier )

AdditionalSecurity = min( safetyShop + (HasSafetyPass ? SAFETY_PASS.add : 0), SAFETY_TOTAL_CAP )
```

- `BaseCash_brut` = la valeur du shop dérivée du niveau (`STATS.BaseCash.valueFor(level)`),
  **inchangée**. C'est ce qu'on continue d'améliorer et de prévisualiser dans le shop.
- `EffectiveBaseCash` = ce qui s'affiche sur le **billboard du bouton**, dans le **HUD**, et
  ce qui sert de **base au paiement**.
- **Plus de `multRebirth` dans la formule de paiement** : il est absorbé par
  `EffectiveBaseCash`.
- `currentMultiplier` (multiplicateur de manche) : boucle inchangée.

Valeurs par facteur :

| Facteur | Attribut d'entrée | Source vérifiable | Valeur |
|---|---|---|---|
| Rebirth | `Rebirths` → `MultRebirth` | persistance (existant) | table actuelle, inchangée |
| Palier argent | `MoneyTierMult` | game pass (palier le + haut) | ×2…×1024, défaut ×1 |
| Communauté | `InCommunity` | `IsInGroup(963505568)` | ×2 si membre, sinon ×1 |
| Safety pass | `HasSafetyPass` | game pass | +0.20 sur `AdditionalSecurity` |

## 3. Attributs (réplication)

On garde le pattern « entrées → valeurs dérivées mirrorées en attributs » de
`PlayerProgressionService`.

**Entrées (écrites par `BoostService`, §5) :**
- `InCommunity : boolean` (défaut `false`)
- `MoneyTierMult : number` (multiplicateur du palier le plus haut possédé, défaut `1`)
- `HasSafetyPass : boolean` (défaut `false`)

**Dérivés (écrits par `PlayerProgressionService.recompute`, §4) :**
- `MoneyMult : number` — total **additif** des facteurs (affichage shop + lisibilité)
- `EffectiveBaseCash : number` — `floor(BaseCash × MoneyMult)`
- `AdditionalSecurity : number` — inclut désormais le safety pass (plafonné)

**Inchangés :** `BaseCash` (brut), `Multiplier`, `MultRebirth`, `Rebirths`, les 3 niveaux.

## 4. Serveur — dérivation (`PlayerProgressionService`)

Introduire une méthode unique `recompute(player)` qui (re)calcule les valeurs combinées
depuis les entrées courantes :

```
recompute(player):
    rawBase      = STATS.BaseCash.valueFor(BaseCashLevel)
    multRebirth  = rebirthMult(Rebirths)                       // déjà mirroré
    tierMult     = attr("MoneyTierMult") ?? 1
    inCommunity  = attr("InCommunity") == true
    moneyMult    = moneyMult(multRebirth, tierMult, inCommunity)   // helper ShopConfig (additif)
    set("MoneyMult", moneyMult)
    set("EffectiveBaseCash", floor(rawBase * moneyMult))

    shopSafety   = STATS.Safety.valueFor(SafetyLevel)
    hasPass      = attr("HasSafetyPass") == true
    set("AdditionalSecurity", effectiveSafety(shopSafety, hasPass))   // helper ShopConfig
```

`recompute` est appelé : après le chargement (`applyLevels`), après `addLevel`, après
`rebirth`, et par `BoostService` après écriture des entrées. `applyLevels` ne pose plus
directement `AdditionalSecurity` (déplacé dans `recompute`) ; il continue de poser les
valeurs brutes `BaseCash`/`Multiplier` et `MultRebirth`.

Nouvelle clé de lecture publique : `ProgressionKey` gagne `"EffectiveBaseCash"` et
`"MoneyMult"` (la boucle de jeu lit `EffectiveBaseCash`).

## 5. Serveur — nouveau `BoostService`

La détection des boosts externes (appels web `MarketplaceService` + `IsInGroup`, et le
signal `PromptGamePassPurchaseFinished`) est une **responsabilité distincte** de la
persistance DataStore → nouveau fichier `server/services/BoostService.ts`.

**Rôle :** résoudre l'ownership et écrire les attributs d'entrée, puis déclencher la
re-dérivation.

```
resolve(player):
    inCommunity = pcall(IsInGroup, COMMUNITY.groupId)            // false si échec
    tierMult    = max mult parmi MONEY_TIERS possédés (UserOwnsGamePassAsync), sinon 1
    hasPass     = UserOwnsGamePassAsync(SAFETY_PASS.gamePassId)  // false si id 0
    set entrées (InCommunity, MoneyTierMult, HasSafetyPass)
    PlayerProgressionService.recompute(player)
```

- **`PlayerAdded`** → `resolve` (en `task.spawn`, les appels web *yield*) ; **et boucle sur
  les joueurs déjà connectés** à l'init (parité avec les autres services / playtests Studio).
- **`MarketplaceService.PromptGamePassPurchaseFinished`** (purchased=true) → re-`resolve`
  le joueur concerné.
- **Re-check communauté** : `IsInGroup` peut devenir vrai *après* la connexion (le joueur
  rejoint le groupe en jeu). Un event léger **`RecheckBoostsEvent` (C→S)** est firé à
  l'ouverture du shop → `resolve`. (Un seul nouvel event de jeu, cf. §8 ; conforme au
  « minimiser les RemoteEvents ».)
- **`id == 0` = inerte** : aucun appel web, traité comme non-possédé. Tout le pipeline
  fonctionne, les boutons sont juste sans effet jusqu'à ce que les IDs soient renseignés.
- Tous les appels web sont en `pcall` ; un échec laisse l'entrée à sa valeur par défaut et
  sera retenté au prochain `resolve`.

**Async / affichage initial :** `EffectiveBaseCash` est d'abord dérivé des niveaux (palier
×1, pas de communauté, pas de pass) dès le chargement de la progression, puis mis à jour
quand `resolve` revient. `RoomService` écoute déjà le changement d'attribut → le billboard
se met à jour tout seul (même pattern que « le load DataStore qui atterrit après l'assign »).

**Boot order (`services/index.ts`)** : insérer `BoostService` **juste après
`PlayerProgressionService`** (il a besoin de `recompute`), avant `RoomService`. Documenter
dans `index.ts` et `ARCHITECTURE.md` §5.

## 6. Shared — config & helpers

### 6.1 `shared/ShopBalance.ts` (les nombres)

```
COMMUNITY = { groupId: 963505568, mult: 2 }

// Paliers argent — le plus haut possédé gagne. gamePassId 0 = inerte.
MONEY_TIERS = [
    { mult: 2,    gamePassId: 0 },
    { mult: 4,    gamePassId: 0 },
    { mult: 8,    gamePassId: 0 },
    { mult: 16,   gamePassId: 0 },
    { mult: 32,   gamePassId: 0 },
    { mult: 64,   gamePassId: 0 },
    { mult: 128,  gamePassId: 0 },
    { mult: 256,  gamePassId: 0 },
    { mult: 512,  gamePassId: 0 },
    { mult: 1024, gamePassId: 0 },
]

SAFETY_PASS     = { add: 0.20, gamePassId: 0 }
SAFETY_TOTAL_CAP = 0.70    // plafond cumulé shop (0.50) + pass (0.20)
```

### 6.2 `shared/ShopConfig.ts` (helpers purs, partagés client/serveur)

- `moneyMult(multRebirth, moneyTierMult, inCommunity): number` — **total additif** :
  `multRebirth + (inCommunity ? COMMUNITY.mult - 1 : 0) + (moneyTierMult - 1)`. Tout futur
  multiplicateur indépendant s'ajoute pareil (`+ (mult - 1)`).
- `effectiveSafety(shopSafety: number, hasPass: boolean): number`
  → `min(shopSafety + (hasPass ? SAFETY_PASS.add : 0), SAFETY_TOTAL_CAP)`
- `nextMoneyTier(currentMult: number): { mult, gamePassId } | undefined`
  → pour l'upsell « palier suivant » du shop (le 1er palier dont `mult > currentMult`).
- (la résolution du « palier le plus haut possédé » vit dans `BoostService`, qui a accès à
  l'ownership ; `ShopConfig` n'expose que la config `MONEY_TIERS` et les helpers d'affichage.)

Le formatage `×N` réutilise les helpers existants (`trimDecimals` / `FormatNumber`).

## 7. Client — animation de paiement (`client/ui/EndGameAnimation.ts`)

- **Signature** : `runEndGameAnimation(frame, baseCash, multiplier, lossMultiplier, onComplete)`
  — **on retire `multRebirth`**. `baseCash` reçu = `EffectiveBaseCash` (déjà boosté).
- **`totalEarn = effectiveBaseCash × multiplier`** (× `lossMultiplier` via la pénalité mort
  existante).
- **Retirer la phase 2b** : suppression de `flyRebirthMultiplierIntoBaseCash`, du bloc
  `hasRebirthBonus`/`REBIRTH_COUNTUP_*` et des constantes `REBIRTH_*`. Le compte-à-rebours
  de taille se fait en une seule passe (phase 2a jusqu'à `grownSize`).
- Le gros nombre de départ (`EffectiveBaseCash`) montre déjà le boost — pas de flourish
  supplémentaire.

## 8. Réseau — events (`shared/Event.ts`)

- **Modifié** `EndGameStartEvent` (S→C) : **retire `multRebirth`** de la charge utile →
  `(baseCash, multiplier, lossMultiplier)` où `baseCash = EffectiveBaseCash`.
- **Nouveau** `RecheckBoostsEvent` (C→S, sans argument) : firé à l'ouverture du shop pour
  re-vérifier l'appartenance au groupe (et l'ownership). Validé/limité côté serveur.

Le reste passe par **attributs répliqués** (pas d'event de réponse) : le shop et le HUD se
rafraîchissent depuis `MoneyMult` / `EffectiveBaseCash` / `InCommunity` / `MoneyTierMult` /
`HasSafetyPass` / `AdditionalSecurity`.

## 9. Serveur — sites de lecture à adapter

- **`modules/ButtonInGameModule.ts`** : lire `EffectiveBaseCash` au lieu de `BaseCash` ;
  **supprimer** la lecture de `multRebirth` et le facteur `multRebirth` des **4** formules de
  paiement ; `BaseCashEvent.FireClient` envoie `EffectiveBaseCash` ; retirer `multRebirth`
  des appels `EndGameButtonModule.enter`.
- **`modules/EndGameButtonModule.ts`** : retirer le paramètre `multRebirth` de `enter` et de
  `EndGameStartEvent.FireClient`.
- **`rooms/RoomService.ts`** : mirrorer `EffectiveBaseCash` (lecture + signal
  `GetAttributeChangedSignal("EffectiveBaseCash")`) au lieu de `BaseCash`.
- **`client/behaviors/EndGameButtonBehavior.ts`** : retirer l'arg `multRebirth`.
- **`client/behaviors/ButtonInGameBehavior.ts`** : `BaseCashEvent` affiche déjà le nombre
  reçu → aucune logique à changer (il montre l'`EffectiveBaseCash`).

## 10. Client — shop : readout + boutons (`ShopItemsController` / nouveau controller)

Portée actée : **readout + communauté (live) + boutons inertes**.

- **Readout multiplicateur** : le joueur voit **chaque multiplicateur indépendant** (rebirth
  ×N, communauté ×2, palier ×N) **et le total additif** `×MoneyMult`. Lecture pure depuis les
  attributs répliqués (`MultRebirth`, `InCommunity`, `MoneyTierMult`, `MoneyMult`).
- **Bouton communauté** : si `InCommunity == false` → bouton « Rejoindre pour ×2 » qui ouvre
  la page du groupe et fire `RecheckBoostsEvent` ; si `true` → état « obtenu ×2 ».
- **Bouton safety pass** : câbler le `RobuxButton` existant de la cellule `DSafety` →
  `PromptGamePassPurchase(SAFETY_PASS.gamePassId)` (inerte si id 0).
- **Bouton palier suivant** : un upsell montrant `nextMoneyTier(MoneyTierMult)` (×suivant) →
  `PromptGamePassPurchase(tier.gamePassId)` (inerte si id 0).
- Rafraîchissement : même pattern que `ShopItemsController` (refresh sur changement des
  attributs concernés ; pas d'event de réponse).

## 11. Studio — travail visuel (via MCP `Roblox_Studio` à l'implémentation)

Le `.rbxl` n'est pas versionné → les instances GUI se créent dans Studio.

- **Billboard du bouton** : *aucune* modif structurelle — `GainText` reçoit déjà la valeur
  ; elle vaudra désormais `EffectiveBaseCash` (changement 100 % serveur).
- **Shop** (`StarterGui.InGameUI.ShopMenu`) : le `Body` est un `UIGridLayout` 4 cellules
  (`AButtonMoney`/`BX5ButtonMoney`/`CMultiplier`/`DSafety`, chacune avec `BuyButton` +
  `RobuxButton` inexploité). À ajouter : un **strip readout** du multiplicateur (Header ou
  nouvelle ligne), une **cellule communauté**, une **cellule palier argent** (upsell). Le
  détail exact (noms d'instances, layout) sera fixé dans le plan ; création via
  `execute_luau`, et on **reporte ce qui est créé/renommé** (cf. CLAUDE.md).

## 12. Persistance

**Aucun changement DataStore, aucune migration.** Les boosts (`InCommunity`,
`MoneyTierMult`, `HasSafetyPass`) sont la **vérité externe** (groupe / game pass), résolus
**à chaque session** par `BoostService` — **non persistés**. `Rebirths`/`MultRebirth` et les
niveaux restent inchangés (`PlayerProgression_v2`).

## 13. Cas limites

- **Lecture « une fois » par session** : `EffectiveBaseCash` et `AdditionalSecurity` sont lus
  **une fois au début du hold** (comme aujourd'hui BaseCash/Safety) → un achat / une
  adhésion en cours de manche ne change pas une manche déjà lancée. Cohérent avec la règle
  existante.
- **Résolution async** : billboard d'abord ×1, puis mis à jour quand l'ownership revient (via
  le signal d'attribut).
- **Échec d'appel web** (`IsInGroup` / `UserOwnsGamePassAsync`) : `pcall`, défaut non-possédé,
  retenté au prochain `resolve`.
- **Palier** : `max` des paliers possédés (un palier supérieur « remplace » naturellement).
- **Plafond safety** : `min(…, 0.70)` (risque ne tombe jamais à 0).
- **Lisibilité** : `EffectiveBaseCash` peut devenir grand (palier jusqu'à ×1024, + rebirth +
  communauté en additif) → s'appuyer sur `FormatCash`/`FormatNumber`.

## 14. Hors scope (revient « un peu plus tard »)

- **UI d'achat complète des 10 paliers argent** : on met **un seul** bouton upsell
  (palier suivant) ; l'échelle complète et son ergonomie seront traitées plus tard.
- **Vrais IDs de game pass** : config à `0` jusqu'à fourniture.
- **Reformulation du menu Rebirth** : le texte « x{mult} money » reste valable (le rebirth
  reste un facteur) ; reformulation cosmétique optionnelle, non bloquante.
- Refonte de la boucle hold/risk/parry : inchangée.

## 15. Critères d'acceptation

1. Le bouton (billboard) et le HUD affichent `EffectiveBaseCash = floor(BaseCash × MoneyMult)`
   avec `MoneyMult = MultRebirth + (communauté ? COMMUNITY.mult−1 : 0) + (MoneyTierMult−1)`
   (bonus additifs), mis à jour quand un facteur change.
2. Paiement = `floor(EffectiveBaseCash × currentMultiplier)` (win/parry/grace) et
   `floor(EffectiveBaseCash × LOOSE_WIN_MULTIPLIER × currentMultiplier)` (mort) — **plus
   aucun `multRebirth`** dans `ButtonInGameModule`.
3. Communauté : membre du groupe `963505568` ⇒ `CommunityMult = 2`, sinon `1`, vérifié
   serveur ; re-checké à l'ouverture du shop.
4. Palier argent : `MoneyTierMult` = mult du palier le plus haut possédé (×1 si aucun) ;
   `gamePassId 0` ⇒ inerte (aucun effet, aucun crash).
5. Safety pass : `AdditionalSecurity = min(safetyShop + 0.20, 0.70)` quand possédé.
6. Animation de fin : part de `EffectiveBaseCash`, compte uniquement le multiplicateur de
   manche, **sans** phase or rebirth ; affiche exactement le montant crédité.
7. `EndGameStartEvent` ne transporte plus `multRebirth` ; `RecheckBoostsEvent` (C→S) existe.
8. Aucune migration DataStore ; saves existants inchangés ; boosts résolus à la session.
9. Shop : readout du multiplicateur + bouton communauté (live) + boutons safety/palier
   (inertes jusqu'aux IDs), rafraîchis depuis les attributs.
10. `ARCHITECTURE.md` mis à jour : §5 boot order (+BoostService), §6.3 payout, §6.4
    `EndGameStartEvent`, §6.6 attributs dérivés + BoostService, §6.8 shop, §7 events, §8
    constantes de tuning.
