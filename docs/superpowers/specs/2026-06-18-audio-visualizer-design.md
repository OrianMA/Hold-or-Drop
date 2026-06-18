# Spec — Audio Visualizer (spectre néon, déco de lobby)

> Date : 2026-06-18
> Statut : design validé, prêt pour plan d'implémentation.

## 1. Objectif

Afficher dans le lobby un (ou plusieurs) **panneau de spectre audio** : des barres
d'égaliseur qui dansent au rythme de la musique de fond (BGM). Élément purement
décoratif et 100 % client — aucune logique serveur, aucune décision de jeu.

Style retenu : **spectrum bars** (barres verticales), ~32 barres, dégradé néon
**cyan → violet**, attaque rapide / chute lente.

## 2. Périmètre

**Inclus**
- Réagit à la **BGM** (playlist `AudioConfig.bgm`).
- Rendu sur une `SurfaceGui` posée sur une **part autonome**, grande, redimensionnable.
- Support de **plusieurs panneaux** : la part est duplicable et plaçable n'importe où,
  ça doit continuer à fonctionner sans modification de code.

**Exclus (non-goals)**
- Ne réagit pas à la musique du bouton (le joueur en hold est dans sa room, caméra sur
  le bouton). La musique du bouton reste un `Sound` classique, **non touchée**.
- Pas de synchronisation inter-joueurs : chaque client voit sa propre BGM locale
  s'afficher (la BGM est un son personnel). Animation potentiellement décalée d'un
  joueur à l'autre — acceptable pour de la déco.
- Pas de presets de couleur configurables en jeu (couleur fixe au build).

## 3. Exigences non-fonctionnelles (bloquantes)

Ces deux points sont des **critères d'acceptation durs** (exigés par l'utilisateur) :

1. **Aucune latence perceptible** entre la musique et les barres.
2. **Aucun freeze / hitch** introduit dans le jeu, mobile inclus.

Garanties intégrées au design :
- `AudioAnalyzer:GetSpectrum()` lit le dernier buffer audio (temps réel, ~ms).
- Boucle d'analyse **throttlée à ~30 Hz** (accumulateur de `dt`), pas 60 — l'œil ne
  voit pas la différence, mais ça divise par 2 le travail et les allocations.
- **Attaque instantanée, chute lente** : montée des barres immédiate sur un beat
  (réactivité), seul le retour est lissé. Pas de lissage en montée (sinon ça traîne).
- **Analyse effectuée une seule fois par frame**, puis appliquée à tous les panneaux.
- **Barres créées une seule fois** : à l'exécution on n'écrit que leur `Size` (Scale Y) ;
  jamais de création/destruction d'instance dans la boucle.
- **Tables réutilisées** entre les frames (pas de réallocation par tick côté nous).
- Asset BGM **préchargé** (`ContentProvider:PreloadAsync`) → pas de stall au 1er play.

## 4. Architecture

### 4.1 Découverte multi-parts — tag CollectionService

- En Studio, la part porteuse est **taguée** `AudioVisualizer` (CollectionService).
  Le tag est copié à la duplication → toute copie est découverte automatiquement,
  où qu'elle soit dans le `Workspace`. Pas de nom ni de chemin en dur.
- Le client, à l'init :
  - `CollectionService:GetTagged("AudioVisualizer")` pour les parts existantes,
  - `GetInstanceAddedSignal("AudioVisualizer")` / `GetInstanceRemovedSignal(...)` pour
    gérer les parts ajoutées/retirées à l'exécution.
- Pour chaque part taguée : créer une `SurfaceGui` + les barres (une fois), enregistrer
  le panneau dans une liste interne. Au retrait : détruire et désenregistrer.

Constante de tag centralisée (ex. `VISUALIZER_TAG = "AudioVisualizer"`).

### 4.2 Pipeline audio (migration BGM uniquement)

`GetSpectrum()` impose la nouvelle API audio. **Seule la BGM migre** ; tout le reste de
`MusicController` (preload + play/stop de la musique de bouton) est inchangé.

```
AudioPlayer(BGM) ─┬─► Wire ─► AudioFader(Volume) ─► Wire ─► AudioDeviceOutput  (audible)
                  └─► Wire ─► AudioAnalyzer                                     (analyse)
```

- **Playlist** : `AudioPlayer.Ended` → piste suivante (set `AssetId` + `Play()`), wrap
  au début. Même logique que l'actuel (`Looping` pour une piste unique).
- **Ducking** (hold) : on tweene `AudioFader.Volume` au lieu de `Sound.Volume`. Le
  `resumeBgm` / `fadeBgm` ciblent le fader. Mêmes durées (`BGM_FADE_OUT`, `BGM_RESUME`).
- L'`AudioAnalyzer` est branché **avant le fader** (sur la sortie de l'`AudioPlayer`) :
  le panneau reste animé même quand la BGM est duckée localement.
- Le module audio expose la référence de l'`AudioAnalyzer` au visualiser (import direct
  ou petit accesseur), sans recréer de source dédiée à l'analyse (pas de double lecture).

### 4.3 Module client `ui/AudioVisualizer.ts`

- `init()` : découvre les parts taguées (4.1), démarre la boucle `RunService` throttlée.
- Frontière de données **`getBands(): number[]`** (le seul point qui connaît la source
  audio) :
  - lit `AudioAnalyzer:GetSpectrum()`,
  - regroupe les bins en **bandes log-espacées** (l'énergie musicale est concentrée dans
    le bas du spectre ; un découpage linéaire laisserait les barres aiguës mortes),
  - normalise → tableau de 32 valeurs dans `[0,1]`,
  - réutilise un buffer existant (pas d'alloc par tick côté nous).
- Lissage par barre : `value = max(target, value - releaseRate*dt)` (attaque instantanée,
  chute lente).
- Application : pour chaque panneau, pour chaque barre, écrire `Size` (Scale Y) = valeur
  lissée. Aucune autre écriture.
- Wiré dans `main.client.ts` après `MusicController.init()`.

### 4.4 Layout redimensionnable (Scale)

- `SurfaceGui` mappée sur la face de la part ; barres positionnées en **Scale**
  (largeur = part/N, hauteur pilotée par la donnée). Changer la `Size` de la part en
  Studio rescale tout, **sans toucher au code**.
- Dégradé cyan → violet appliqué par barre (couleur fixe au build).

## 5. Côté Studio (réalisé via MCP)

- Créer `Workspace/Environment/AudioVisualizer` : `Part` ancrée, taille de panneau par
  défaut (l'utilisateur ajuste ensuite). La **taguer** `AudioVisualizer`.
- Rien d'autre à authorer : la `SurfaceGui` et les barres sont créées par le client.
- L'utilisateur peut déplacer / redimensionner / dupliquer la part librement.

## 6. Validation & filet de sécurité

- **Avant de figer l'implémentation** : tester `GetSpectrum()` en Studio (`execute_luau`)
  avec un `AudioPlayer` réel pour confirmer qu'il renvoie des données non vides côté
  client (des retours forum signalent des cas de tableau vide).
- **Fallback** : si `GetSpectrum()` ne convient pas, `getBands()` bascule sur
  `Sound.PlaybackLoudness` (valeur unique répartie sur les barres avec variation/lissage)
  **sans rien changer d'autre** — c'est tout l'intérêt de la frontière `getBands()`.
  Dans ce cas la migration BGM (4.2) peut même être évitée.

## 7. Fichiers touchés

| Fichier | Changement |
|---|---|
| `client/audio/MusicController.ts` | BGM : `Sound` → `AudioPlayer`+`AudioFader`+`AudioDeviceOutput`+`Wire`+`AudioAnalyzer`. Ducking via fader. Bouton inchangé. Expose l'analyzer. |
| `client/ui/AudioVisualizer.ts` | **Nouveau** : découverte tag, boucle 30 Hz, `getBands()`, rendu des barres. |
| `client/main.client.ts` | +1 ligne : init du visualiser après `MusicController`. |
| `shared/AudioConfig.ts` | Inchangé (réutilise `bgm`). |
| `ARCHITECTURE.md` | Maj §6.10 (audio) + mention du nouveau système visualiser. |

## 8. Risques & mitigations

- **Migration BGM** (seule vraie zone de risque) : le choreography duck/fade est délicat.
  Mitigation : changement contenu à la partie BGM, durées et comportement préservés,
  test manuel du cycle hold → release / mort → respawn.
- **`GetSpectrum()` vide** : couvert par la validation Studio + fallback (§6).
- **Nombre de panneaux élevé** : l'analyse reste O(1) par frame ; seul le rendu croît
  linéairement (barres = écritures de `Size`, très bon marché). Pas de cap nécessaire au
  départ.

## 9. Critères d'acceptation

- [ ] La BGM joue normalement (playlist, loop, ducking pendant le hold, reprise à la fin).
- [ ] La musique du bouton est inchangée.
- [ ] Le(s) panneau(x) dansent au rythme de la BGM, sans latence perceptible.
- [ ] Dupliquer la part en Studio (ailleurs) → la copie fonctionne sans toucher au code.
- [ ] Redimensionner la part → les barres se rescalent proprement.
- [ ] Aucun freeze/hitch mesurable introduit (vérif. en jeu, mobile inclus).
- [ ] `GetSpectrum()` validé en Studio, ou fallback `PlaybackLoudness` en place.
