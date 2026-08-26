# Payout Tiers — escalade sonore et visuelle de l'écran de fin

Date : 2026-08-26
Portée : `ButtonFinishGame` / `client/ui/EndGameAnimation.ts` (§6.4 de `ARCHITECTURE.md`)

## Problème

La phase 2 du paiement (le count-up `effectiveBaseCash → totalEarn`) est le moment
« je gagne de l'argent » de la boucle, et elle est muette et sans particule : 0,6 s,
le texte grossit, devient rouge, fin. Le seul son du paiement arrive en phase 3, où
les 8 chunks jouent huit fois le même `ka-ching` au même pitch — ça sonne répétition,
pas jackpot.

Conséquence : un run à ×1.4 et un run à ×80 produisent **exactement la même
animation**. Rien ne dit au joueur qu'il vient de faire un gros coup.

## Objectif

Rendre l'ampleur du gain lisible en temps réel : plus le multiplicateur est haut,
plus c'est fort, plus c'est gros, plus il y a de particules — avec de l'argent qui
tombe du ciel à chaque paiement.

## Calibrage des seuils

Le multiplicateur atteint dépend de **deux** stats :
- la **Rocket Speed**, linéairement : `mult = 1 + rocketSpeed × G(durée)`
  (`shared/RocketGameConfig.multiplierAfter`) ;
- la **Resistance**, qui allonge la durée de vol
  (`safeWindow + 7 × riskScale^(-1/3)` — de 7 s à Resistance 0 jusqu'à 22.5 s à 100).

Trois options, dans l'ordre où elles ont été écartées :

1. **Seuils absolus** (×2/×10/×100) — inatteignables en early, saturés en late.
   L'animation redevient identique à chaque run dans les deux cas.
2. **Ratio à la moyenne** (`mult / moyenne`) — insuffisant. La `safeWindow` de la
   Resistance est **déterministe**, donc elle écrase la variance *relative* : à
   Resistance 0 le meilleur centile vaut ~3.9× la moyenne, à Resistance 100 seulement
   ~1.5×. Un palier « ≥ 2.5× ta moyenne » deviendrait inatteignable en fin de
   progression — acheter de la Resistance rendrait les paiements **moins**
   spectaculaires, exactement l'inverse du but.
3. **Centiles de la distribution de vol du joueur** — retenu. « Ce run bat 90 % de tes
   runs » veut dire la même chose à toute Rocket Speed et à toute Resistance.

Le calcul est **analytique**, pas simulé : la durée de vol au centile *p* vaut
`safeWindow + médiane × riskScale^(-1/3) × e^(σ·z_p)`, qu'on repasse dans
`multiplierAfter`. Centiles visés : 35 / 60 / 78 / 90 / 96 / 99 / 99.7 / 99.95, plus un
palier 0 toujours franchi.

**Aucun seuil n'est jamais affiché au joueur** — les paliers ne pilotent que le son et
les particules. Abandonner les nombres ronds ne coûte donc aucune lisibilité, ce qui
lève la seule objection qui avait fait préférer l'échelle absolue au départ.

### Loi de vol déplacée vers `shared/`

`FLIGHT_TIME_MEAN` / `_SIGMA` / `_MEDIAN` vivaient dans
`server/modules/ButtonInGameModule.ts`. Le client en a désormais besoin, donc elles
passent dans `shared/ResistanceCurve.ts` et le serveur les importe — une seule source de
vérité. Deux fonctions pures s'y ajoutent :

- `flightTimeAtZ(resistance, z)` — l'**inverse** du tirage ;
- `expectedFlightTime(resistance)` — forme fermée, σ s'annule car `E[e^(σZ)] = e^(σ²/2)`
  annule exactement le `e^(-σ²/2)` de la médiane. Reproduit tous les repères documentés
  de la courbe de Resistance (L20 → 13.3 s, L50 → 17.0 s, L100 → 22.5 s).

`EndGameAnimation` lit les attributs répliqués `RocketSpeed` et `Resistance` du
`LocalPlayer`. `Resistance` porte déjà la valeur **effective** (game pass inclus), donc
exactement celle que le modèle de risque serveur consomme.

## Architecture

### `client/ui/PayoutTiers.ts` (nouveau)

Un seul rôle : décrire l'échelle et dire quels paliers un multiplicateur franchit.

- `TIER_PERCENTILE_Z` — les 8 quantiles normaux des centiles visés. Le seuil du palier
  *i* est recalculé **par run** depuis `(rocketSpeed, resistance)`.
- Le palier 0 n'a pas de centile : son seuil vaut `STARTING_MULTIPLIER`, donc **tout**
  paiement franchit au moins un palier — il y a toujours un son et une pluie légère.
- `MAX_PLAYED = 3` — seuls les 3 derniers paliers franchis se jouent, l'escalade
  reste courte et les paliers joués sont toujours les plus impressionnants.
- L'intensité est **dérivée de l'index absolu** du palier (0..8), pas écrite à la
  main : la monotonie est garantie et le tuning se fait sur deux bornes.

Champs interpolés de l'index 0 à l'index max :

| Champ            | index 0        | index 8 (p99.95) |
| ---------------- | -------------- | ---------------- |
| `pitch`          | 1.00           | 1.30             |
| `volume`         | 0.5            | 1.0              |
| `burstCount`     | 6              | 36               |
| `rainCount`      | 8              | 40               |
| `punch`          | 1.12           | 1.40             |
| `color`          | rouge clair    | or plein         |
| `goldRain`       | à partir de ×25 |                 |
| `bigReward`      | à partir de ×25 |                 |

`rainCount` est plafonné à 40 (et non 55) pour que le palier max — 40 billets + 20 en
or — tienne sous `MAX_LIVE_DROPS` sans avoir à évincer sa propre pluie d'or.

Seuils par index : `GOLD_RAIN_INDEX = 3` (p78) fait tomber des lingots avec les billets,
`BIG_REWARD_INDEX = 4` (p90) ajoute `sfx.bigPayout`.

### Déluge de lingots

Le **climax** d'une escalade qui atteint `INGOT_DOWNPOUR_INDEX = 5` (p96, top 4 % des
runs) **remplace** la pluie de billets par 40–62 lingots. Une pluie d'or pure se lit
mieux qu'un mélange, et comme le plafond de `CriticalRain` évince les plus anciennes
gouttes, l'écran bascule intégralement en or. Au plus une fois par paiement.

L'image de lingot est celle qui existait déjà : `rbxassetid://13506500866`, nommée
« minecraft gold ingot » — c'est le `RAIN_IMAGE` du Critical Claim. Aucun nouvel asset.

API : `tiersCrossed(multiplier, rocketSpeed, resistance)`,
`topTierIndex(multiplier, rocketSpeed, resistance)`.

### Audio

- `shared/AudioConfig.ts` : ajout de `sfx.bigPayout = { id: "rbxassetid://3406813517",
  volume: 0.9 }` — même asset que `perfectClaim`, volume propre (précédent existant :
  `billPop` vs `uiClick`).
- `client/audio/CashSound.ts` : `play(options?: { pitch?, volume? })` pose
  `PlaybackSpeed` / `Volume` sur le clone. Ajout de `playBigPayout()`. Les signatures
  existantes restent valides sans argument.

### Particules paramétrables

`MoneyBurst.play(origin?, options?)` accepte `options.count` ; `CriticalRain.play(image?,
options?)` accepte `count`, `band` (hauteur de la bande de départ, donc la **durée** de la
pluie) et `zIndex` (plan de rendu). Les défauts sont les constantes actuelles, donc tous
les appels existants (claim, récompense journalière, quêtes) gardent leur comportement.

`MoneyBurst.gatherTo` devient optionnel — l'escalade veut une gerbe qui retombe, pas une
aspiration.

Garde-fou mobile : chaque module borne les particules **vivantes** (60 billets pour
`MoneyBurst`, 70 gouttes pour `CriticalRain`) — c'est ce qui protège le cas où trois
paliers empilent leurs salves en une seconde.

Le plafond **évince les plus anciennes** particules au lieu de tronquer la nouvelle
salve. Tronquer produirait l'inverse du but recherché : le dernier palier, le plus
gros, arriverait sur un écran déjà plein et n'afficherait presque rien, donc l'effet
**décroîtrait** à mesure que le gain grossit.

### Phase 2 — l'escalade

Le proxy `NumberValue` d'`animateCash` fire déjà `Changed` à chaque frame. On y branche
la détection : `multCourant = valeur / effectiveBaseCash` ; dès qu'il dépasse le seuil
suivant, le palier se déclenche.

Durée du count-up : `0.6 s + 0.2 s × nb de paliers`, plafonnée à **1.2 s**.

Chaque palier franchi joue :
- `playCashSound({ pitch, volume })` — le pitch qui monte fait entendre un combo ;
- `playBigPayout()` à partir de ×25 ;
- un punch du texte via un `UIScale` dédié : saut instantané à `tier.punch` puis
  recalage à 1 (0.26 s, Back.Out) ;
- `MoneyBurst.play(centreDuLabel, { count: burstCount })` ;
- `CriticalRain.play(BILLET, rainCount)`, plus `CriticalRain.play(LINGOT, rainCount / 2)`
  quand `goldRain` — ou, sur un climax en déluge, **uniquement** les lingots ;
- la couleur du palier sur `BaseCashText`.

**Changement de comportement assumé** : pendant la phase 2, la couleur n'est plus
tweenée par `animateCash` — ce sont les paliers qui la posent.
`BASE_CASH_TARGET_COLOR` devient la couleur de l'index 0.

**Pourquoi le punch passe par un `UIScale` et non par `TextSize`.** Roblox **plafonne
`TextSize` à 100** (vérifié en jeu : 101, 125 et 200 lisent tous 100) et `BaseCashText`
démarre à 85. Un dépassement d'easing sur la taille serait donc silencieusement écrêté,
précisément sur les gros paliers où le punch compte le plus. Le `UIScale` n'a pas cette
limite, et comme c'est une instance séparée son tween ne croise jamais celui de la
taille/couleur — il peut se dérouler par-dessus le segment suivant.

Pour la même raison, `BASE_CASH_MAX_SIZE_INCREASE` passe de 40 à **15** : 85 + 15 = 100
exactement. À 40 la cible valait 125, écrêtée à 100, donc l'agrandissement saturait au
milieu du count-up au lieu de suivre le nombre jusqu'au bout (défaut préexistant).

Pas de screen shake : les phases 3 et 4 lisent des `AbsolutePosition` pour viser le
HUD, secouer le `ScreenGui` casserait les trajectoires.

### Phase 3 — crescendo au lieu de spam

- `FLOATING_TEXT_COUNT` devient `8 + index du palier max`, plafonné à 16 (à 2 par palier
  la rafale saturait dès ×5, donc bien trop tôt dans la progression).
- `MoneyDisplay.addVisual(amount, soundOptions?)` gagne un paramètre optionnel ;
  `EndGameAnimation` y passe un pitch montant de 1.00 à 1.25 sur les n chunks. Les
  `ka-ching` deviennent un arpège. Les autres appelants ne changent pas.

### Phase 4 — l'atterrissage

`flyBaseCashToHud` et `FINAL_MOVE_DELAY` décrivent une phase 4 qui **n'est pas branchée**
dans l'orchestrateur : la phase 3 masque déjà le label sur son dernier chunk. Code mort
laissé en place (hors périmètre), mais l'en-tête du fichier le signale désormais.

Le dernier « boum » est donc joué à la fin de la **phase 3**, quand la dernière liasse
atterrit : `MoneyBurst.play(centreHUD, { count: 10 + index })` et `playBigPayout()` si le
palier max est un gros lot.

### Annulation

`cancelActiveRun()` appelle désormais `MoneyBurst.clear()` et `CriticalRain.clear()` :
la pluie vit jusqu'à 9 s alors que le paiement dure ~4 s, sans ça elle déborderait sur
l'écran suivant. Même traitement sur le chemin rebirth (`FloatingCash.isStale`).

## Fichiers touchés

| Fichier | Nature |
| --- | --- |
| `src/client/ui/PayoutTiers.ts` | nouveau |
| `src/shared/ResistanceCurve.ts` | loi de vol partagée + `flightTimeAtZ` / `expectedFlightTime` |
| `src/server/modules/ButtonInGameModule.ts` | importe la loi de vol au lieu de la redéclarer |
| `src/shared/AudioConfig.ts` | +1 entrée `bigPayout` |
| `src/client/audio/CashSound.ts` | options pitch/volume, `playBigPayout` |
| `src/client/ui/MoneyBurst.ts` | `options.count`, plafond de billets vivants |
| `src/client/ui/CriticalRain.ts` | options `count`/`band`/`zIndex`, plafond de gouttes vivantes |
| `src/client/ui/MoneyDisplay.ts` | `addVisual` accepte des options de son |
| `src/client/ui/EndGameAnimation.ts` | phases 2 / 3 / 4 + annulation |
| `ARCHITECTURE.md` | §6.4, §6.21, §6.23 |

Aucun changement serveur, aucun nouveau RemoteEvent : le multiplicateur claimé arrive
déjà dans `EndGameStartEvent`.

## Vérification

- `expectedFlightTime` reproduit **tous** les repères documentés de la courbe de
  Resistance (L1/L5/L10/L20/L50/L100), au centième.
- L'index du palier atteint par centile de run est **identique** sur six configurations
  de progression (speed 1→200, resistance 0→100) : 0/0/1/2/3/4/6 pour p10→p99. Le
  calibrage est donc bien invariant.
- Déluge de lingots vérifié en jeu : au climax d'un run top 1 %, l'écran passe de
  44 billets + 26 lingots à **70 lingots et 0 billet**, plafonds tenus (70 / 60).
- `PayoutTiers` compilé exercé en jeu (`execute_luau`, datamodel Client) : pitch,
  volume, gerbe, pluie et punch conformes.
- Escalade de particules rejouée pour un run ×140 : demandes croissantes (22→25→28
  billets), plafonds respectés par éviction (60 / 70), et **toutes** les gouttes en
  `ZIndex` 0 donc derrière le montant (`ZIndexBehavior = Sibling` confirmé).
- Plafond `TextSize` et absence de plafond sur `UIScale` mesurés sur le vrai label.

L'animation de bout en bout n'a **pas** pu être jouée via le MCP : dans le sandbox
`execute_luau`, aucun tween TweenService n'avance (vérifié sur un `NumberValue` neutre,
Heartbeat tournant normalement), donc tout le code qui bloque sur `Completed:Wait()`
reste figé. Le rendu final (timing ressenti, mixage sonore) reste à valider en jeu.

## Hors périmètre

- Screen shake (casse le ciblage du HUD).
- Pluie de fond continue pendant toute la popup (charge mobile, masque le montant).
