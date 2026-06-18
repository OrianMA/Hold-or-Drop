# Audio Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher dans le lobby un visualiser de spectre néon (barres d'égaliseur) qui danse au rythme de la BGM, rendu sur une `SurfaceGui` posée sur une (ou plusieurs) part(s) autonome(s) découverte(s) par tag CollectionService.

**Architecture:** 100 % client / présentation. La BGM est migrée vers la nouvelle API audio (`AudioPlayer` + `AudioDeviceOutput` + `AudioAnalyzer` reliés par `Wire`) pour pouvoir lire `AudioAnalyzer:GetSpectrum()`. Un module client découvre toutes les parts taguées `AudioVisualizer`, leur construit une SurfaceGui + barres une seule fois, puis une boucle throttlée à ~30 Hz lit le spectre **une fois** et l'applique à tous les panneaux (attaque instantanée, chute lente).

**Tech Stack:** roblox-ts (`rbxtsc`), Rojo, services `@rbxts/services` (CollectionService, RunService, SoundService, TweenService, ContentProvider, Players). Nouvelle API audio Roblox. Validation via build + playtest Studio (MCP `Roblox_Studio`).

---

## Note sur la vérification (pas de framework de test)

Ce projet n'a **pas** de harness de tests unitaires (pas de TestEZ/jest), et la fonctionnalité est
visuelle + dépendante du moteur audio. Conformément à `CLAUDE.md` (simplicité, pas de nouveau
framework), la vérification de chaque tâche est :

1. **Compilation** : `npm run build` → doit terminer sans erreur TypeScript.
2. **Playtest Studio** : via le MCP `Roblox_Studio` (`start_stop_play`, `get_console_output`,
   `screen_capture`, `execute_luau`).

Les noms/propriétés de la nouvelle API audio ont été vérifiés contre les typings installés
(`node_modules/@rbxts/types`) : `AudioPlayer.Asset` (string), `.Volume` (0–10), `.Looping`,
`.Play()`, `.Ended` ; `AudioAnalyzer.SpectrumEnabled`, `.WindowSize` (`Enum.AudioWindowSize`),
`:GetSpectrum(): Array<number>` ; `Wire.SourceInstance/SourceName/TargetInstance/TargetName` ;
`AudioDeviceOutput.Player` ; `SurfaceGui.SizingMode` (`Enum.SurfaceGuiSizingMode.PixelsPerStud`),
`.PixelsPerStud`, `.LightInfluence`, `.Adornee`, `.Face`.

---

## File Structure

| Fichier | Responsabilité |
|---|---|
| `src/client/audio/MusicController.ts` | **Modifié** : BGM migrée vers la nouvelle API audio + expose l'`AudioAnalyzer`. Musique de bouton (Sound classique) inchangée. |
| `src/client/ui/AudioVisualizer.ts` | **Créé** : découverte par tag, construction des panneaux, boucle 30 Hz, `getBands()`, rendu. |
| `src/client/main.client.ts` | **Modifié** : init du visualiser après `MusicController.init()`. |
| `ARCHITECTURE.md` | **Modifié** : §6.10 (audio) + nouvelle sous-section visualiser. |

Studio (via MCP, pas de fichier) : une `Part` `Workspace/Environment/AudioVisualizer` taguée `AudioVisualizer`.

---

## Task 1 : GATE — valider `GetSpectrum()` en Studio (go/no-go)

**But :** confirmer empiriquement que `AudioAnalyzer:GetSpectrum()` renvoie des données non vides
côté client avec un `AudioPlayer`, **avant** de toucher au code. Si non → bascule sur le fallback
`PlaybackLoudness` (voir fin de tâche) et la migration BGM (Task 3) est annulée.

**Files:** aucun (exécution Studio via MCP).

- [ ] **Step 1 : S'assurer que le bon Studio est actif**

MCP : `list_roblox_studios` → `set_active_studio` sur l'instance "Tenir ou lâcher".

- [ ] **Step 2 : Lancer le playtest** (GetSpectrum renvoie vide hors run / côté serveur)

MCP : `start_stop_play` (start). Attendre que le jeu tourne.

- [ ] **Step 3 : Exécuter la sonde sur le client**

MCP `execute_luau` (contexte client si l'outil le permet, sinon via un LocalScript injecté). Snippet :

```lua
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local player = Instance.new("AudioPlayer")
player.Asset = "rbxassetid://93145377732572" -- BGM (AudioConfig.bgm.playlist[1])
player.Looping = true
player.Volume = 0.3
player.Parent = SoundService

local output = Instance.new("AudioDeviceOutput")
output.Player = Players.LocalPlayer
output.Parent = player

local analyzer = Instance.new("AudioAnalyzer")
analyzer.SpectrumEnabled = true
analyzer.WindowSize = Enum.AudioWindowSize.Medium
analyzer.Parent = player

local w1 = Instance.new("Wire"); w1.SourceInstance = player; w1.SourceName = "Output"; w1.TargetInstance = output; w1.TargetName = "Input"; w1.Parent = player
local w2 = Instance.new("Wire"); w2.SourceInstance = player; w2.SourceName = "Output"; w2.TargetInstance = analyzer; w2.TargetName = "Input"; w2.Parent = player

player:Play()
task.wait(1.5) -- laisser le buffer se remplir
local spectrum = analyzer:GetSpectrum()
print("SPECTRUM_BINS=", #spectrum, " RMS=", analyzer.RmsLevel, " SAMPLE=", spectrum[1], spectrum[math.floor(#spectrum/2)])
player:Destroy()
```

- [ ] **Step 4 : Lire le verdict**

MCP `get_console_output`.
- **GO** si `SPECTRUM_BINS` > 0 et des valeurs non nulles apparaissent. Noter la valeur de
  `SPECTRUM_BINS` (taille du tableau pour `Enum.AudioWindowSize.Medium`) et l'ordre de grandeur
  des valeurs RMS (sert à régler `SPECTRUM_SCALE` en Task 6).
- **NO-GO** si `SPECTRUM_BINS=0` partout → passer au fallback ci-dessous.

- [ ] **Step 5 : Arrêter le playtest**

MCP : `start_stop_play` (stop).

**Si NO-GO (fallback PlaybackLoudness) :**
- Task 3 (migration BGM) est **annulée** : la BGM reste un `Sound` classique.
- Dans Task 5, remplacer le corps de `readBands` par la version loudness :

```ts
// Fallback : pas de vraies fréquences → on répartit la loudness globale sur les
// barres avec un profil fixe + un peu de bruit, pour un effet égaliseur stylisé.
function readBands(target: number[]): void {
	const sound = MusicController.getBgmSound();          // accesseur ajouté à MusicController
	const loudness = sound !== undefined ? sound.PlaybackLoudness / 1000 : 0;
	for (let i = 0; i < BAR_COUNT; i++) {
		const profile = 0.6 + 0.4 * math.sin((i / BAR_COUNT) * math.pi);   // bosse centrale
		const noise = 0.85 + 0.15 * math.noise(i * 0.5, os.clock() * 1.5);  // scintillement
		target[i] = math.clamp(loudness * profile * noise * 2.2, 0, 1);
	}
}
```
- Et exposer `getBgmSound(): Sound | undefined` au lieu de `getBgmAnalyzer()`.

> Le reste du plan suppose le cas **GO**.

- [ ] **Step 6 : Commit** (note de décision, aucun code encore)

```bash
git commit --allow-empty -m "chore: GetSpectrum validé en Studio (go) — audio visualizer"
```

---

## Task 2 : Studio — créer la part taguée `AudioVisualizer`

**But :** créer la part porteuse, ancrée, taguée, dans le lobby. L'utilisateur la repositionnera /
redimensionnera / dupliquera ensuite.

**Files:** aucun (Studio via MCP).

- [ ] **Step 1 : Créer + taguer la part**

MCP `execute_luau` (en mode édition, hors playtest, pour que ça persiste dans le place) :

```lua
local CollectionService = game:GetService("CollectionService")
local env = workspace:WaitForChild("Environment")

local existing = env:FindFirstChild("AudioVisualizer")
if existing then existing:Destroy() end

local part = Instance.new("Part")
part.Name = "AudioVisualizer"
part.Anchored = true
part.CanCollide = false
part.CanTouch = false
part.CanQuery = false
part.Castshadow = false
part.Size = Vector3.new(16, 9, 0.5)         -- panneau 16:9, redimensionnable ensuite
part.Color = Color3.fromRGB(10, 12, 20)
part.Material = Enum.Material.SmoothPlastic
part.Position = Vector3.new(0, 12, 0)        -- placeholder ; à repositionner dans le lobby
part.Parent = env

CollectionService:AddTag(part, "AudioVisualizer")
print("CREATED_TAGGED=", part:GetFullName(), CollectionService:HasTag(part, "AudioVisualizer"))
```

> Note : `Front` (`+Z`) est la face rendue par défaut (Task 5). Oriente la part pour que sa face
> Front regarde la zone joueurs.

- [ ] **Step 2 : Vérifier**

MCP `get_console_output` → confirmer `CREATED_TAGGED= ... true`. Optionnel : `search_game_tree`
sur `Workspace.Environment` pour voir la part.

- [ ] **Step 3 : Commit** (rien dans le repo ; le place n'est pas versionné)

```bash
git commit --allow-empty -m "chore(studio): part AudioVisualizer taguée créée dans le lobby"
```

---

## Task 3 : Migrer la BGM vers la nouvelle API audio (+ exposer l'analyzer)

**But :** remplacer le `Sound` BGM par `AudioPlayer` + `AudioDeviceOutput` + `AudioAnalyzer` reliés
par `Wire`, en préservant playlist, loop, ducking, reprise. **Musique de bouton inchangée.**

> Déviation vs spec (assumée) : on ducke en tweenant `AudioPlayer.Volume` (l'API a sa propre
> propriété `Volume` 0–10), **sans `AudioFader`**. Conséquence : pendant un hold *local*, le panneau
> du joueur en hold s'aplatit — mais il est dans sa room, caméra sur le bouton, il ne le regarde pas.
> Les autres joueurs du lobby ont leur propre BGM non duckée → effet préservé.

**Files:**
- Modify: `src/client/audio/MusicController.ts` (remplacement complet du fichier)

- [ ] **Step 1 : Remplacer le contenu de `MusicController.ts`**

```ts
import { ContentProvider, Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Musique client : BGM (nouvelle API audio, pour exposer un spectre au visualiser) +
// musique du bouton (Sound classique, inchangée). SFX restent à leurs call sites.

// La BGM ducke vite au début d'un hold puis revient lentement une fois le run terminé.
const BGM_FADE_OUT = 0.4;
const BGM_RESUME = 3;

// BGM via la nouvelle API audio : AudioPlayer -> AudioDeviceOutput (audible) et
// AudioPlayer -> AudioAnalyzer (analyse spectre pour le visualiser de lobby).
let bgmPlayer: AudioPlayer | undefined;
let bgmAnalyzer: AudioAnalyzer | undefined;
let bgmIndex = 0;
let bgmFadeTween: Tween | undefined;
let bgmDucked = false;

// Musique du bouton — Sound classique, créée/jouée à la demande.
let buttonMusic: Sound | undefined;

function createSound(id: string, volume: number, name: string, looped: boolean): Sound {
	const sound = new Instance("Sound");
	sound.Name = name;
	sound.SoundId = id;
	sound.Volume = volume;
	sound.Looped = looped;
	sound.Parent = SoundService;
	return sound;
}

function createWire(source: Instance, target: Instance, parent: Instance): void {
	const wire = new Instance("Wire");
	wire.SourceInstance = source;
	wire.SourceName = "Output";
	wire.TargetInstance = target;
	wire.TargetName = "Input";
	wire.Parent = parent;
}

// Fait fondre le volume de la BGM vers une cible. Annule tout fade en cours pour
// qu'un hold -> release rapide ne laisse pas deux tweens se battre sur Volume.
function fadeBgm(targetVolume: number, duration: number): void {
	if (!bgmPlayer) return;
	bgmFadeTween?.Cancel();
	bgmFadeTween = TweenService.Create(
		bgmPlayer,
		new TweenInfo(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume: targetVolume },
	);
	bgmFadeTween.Play();
}

// Fin du run — ramène la BGM lentement. No-op si elle n'est pas duckée.
function resumeBgm(): void {
	if (!bgmDucked) return;
	bgmDucked = false;
	fadeBgm(AudioConfig.bgm.volume, BGM_RESUME);
}

function playBgmTrack(index: number): void {
	if (!bgmPlayer) return;
	const playlist = AudioConfig.bgm.playlist;
	if (playlist.size() === 0) return;
	bgmIndex = index % playlist.size();
	const id = playlist[bgmIndex];
	if (id === undefined) return;
	bgmPlayer.Asset = id;
	bgmPlayer.Play();
}

export const MusicController = {
	init(): void {
		// BGM. Une piste boucle via Looping ; plusieurs pistes avancent sur Ended et
		// reviennent à la première.
		const playlist = AudioConfig.bgm.playlist;
		const firstTrack = playlist[0];
		if (firstTrack !== undefined) {
			const player = new Instance("AudioPlayer");
			player.Name = "BGM";
			player.Volume = AudioConfig.bgm.volume;
			player.Looping = playlist.size() === 1;
			player.Asset = firstTrack;
			player.Parent = SoundService;

			const output = new Instance("AudioDeviceOutput");
			output.Player = Players.LocalPlayer;
			output.Parent = player;

			const analyzer = new Instance("AudioAnalyzer");
			analyzer.SpectrumEnabled = true;
			analyzer.WindowSize = Enum.AudioWindowSize.Medium;
			analyzer.Parent = player;

			createWire(player, output, player);
			createWire(player, analyzer, player);

			bgmPlayer = player;
			bgmAnalyzer = analyzer;

			if (playlist.size() > 1) {
				player.Ended.Connect(() => playBgmTrack(bgmIndex + 1));
			}

			// Précharge l'asset pour éviter un stall au premier Play.
			task.spawn(() => {
				ContentProvider.PreloadAsync([player]);
			});
			playBgmTrack(0);
		}

		// Musique du bouton — créée + préchargée maintenant (pas de stall au 1er hold), bouclée.
		buttonMusic = createSound(AudioConfig.buttonGame.id, AudioConfig.buttonGame.volume, "ButtonGameMusic", true);
		task.spawn(() => ContentProvider.PreloadAsync([buttonMusic!]));

		// Un respawn (typiquement après explosion mortelle) termine le run -> ramène la BGM.
		Players.LocalPlayer.CharacterAdded.Connect(() => resumeBgm());
	},

	// Début d'un hold — ducke la BGM et joue la musique de bouton bouclée.
	playButtonMusic(): void {
		fadeBgm(0, BGM_FADE_OUT);
		bgmDucked = true;
		if (!buttonMusic) return;
		buttonMusic.TimePosition = 0;
		buttonMusic.Play();
	},

	// Release ou explosion — stoppe seulement la musique de bouton. Idempotent.
	stopButtonMusic(): void {
		buttonMusic?.Stop();
	},

	// Fin du run — respawn après mort, ou fin de l'animation de payout.
	resumeBgm,

	// Permet au visualiser de lire le spectre de la BGM (client uniquement).
	getBgmAnalyzer(): AudioAnalyzer | undefined {
		return bgmAnalyzer;
	},
};
```

- [ ] **Step 2 : Compiler**

Run : `npm run build`
Expected : compilation OK, aucune erreur TypeScript.

- [ ] **Step 3 : Playtest Studio — la BGM marche toujours**

MCP `start_stop_play` (start). Vérifier (oreille + `get_console_output` pour absence d'erreur) :
- la BGM joue au spawn ;
- déclencher un hold → la BGM ducke et la musique de bouton joue ;
- release / mort → musique de bouton stoppe ;
- fin de run / respawn → la BGM revient en ~3 s.
MCP `start_stop_play` (stop).

- [ ] **Step 4 : Commit**

```bash
git add src/client/audio/MusicController.ts
git commit -m "feat(audio): BGM via la nouvelle API audio (AudioPlayer + AudioAnalyzer)"
```

---

## Task 4 : Module visualiser `ui/AudioVisualizer.ts`

**But :** découvrir les parts taguées, construire panneaux + barres une fois, et animer à 30 Hz.

**Files:**
- Create: `src/client/ui/AudioVisualizer.ts`

- [ ] **Step 1 : Créer le fichier**

```ts
import { CollectionService, Players, RunService } from "@rbxts/services";
import { MusicController } from "client/audio/MusicController";

// Visualiser de spectre du lobby : des barres d'égaliseur rendues sur chaque part
// taguée VISUALIZER_TAG. Le spectre de la BGM est lu UNE fois par tick puis appliqué
// à tous les panneaux. 100 % client, présentation uniquement.

const VISUALIZER_TAG = "AudioVisualizer";

// --- réglages -------------------------------------------------------------
const BAR_COUNT = 32;
const UPDATE_HZ = 30; // fréquence analyse/rendu (throttlée, pas 60)
const RELEASE_PER_SEC = 2.2; // chute lente ; l'attaque est instantanée
const SPECTRUM_SCALE = 8; // mappe les niveaux RMS -> [0,1] ; à régler en Task 6
const MIN_BAR_SCALE = 0.02; // les barres ne s'effondrent jamais totalement
const FREQ_MIN = 20; // Hz, bande la plus basse
const FREQ_MAX = 16000; // Hz, bande la plus haute
const SAMPLE_RATE_HALF = 24000; // GetSpectrum couvre 0..24 kHz
const BAR_GAP_SCALE = 0.3; // fraction d'un slot laissée en espace
const COLOR_LEFT = Color3.fromRGB(86, 224, 255); // cyan
const COLOR_RIGHT = Color3.fromRGB(157, 107, 255); // violet

// Un panneau rendu (les barres vivent dans une SurfaceGui sur une part taguée).
interface Panel {
	gui: SurfaceGui;
	bars: Array<Frame>;
}

const panels = new Map<BasePart, Panel>();

// Buffers réutilisés entre les ticks (aucune allocation par tick côté nous).
const smoothed: Array<number> = [];
const bandBuf: Array<number> = [];
for (let i = 0; i < BAR_COUNT; i++) {
	smoothed[i] = 0;
	bandBuf[i] = 0;
}

const SLOT = 1 / BAR_COUNT;
const BAR_WIDTH = SLOT * (1 - BAR_GAP_SCALE);

function buildPanel(part: BasePart): Panel {
	const gui = new Instance("SurfaceGui");
	gui.Name = "AudioVisualizer";
	gui.Face = Enum.NormalId.Front;
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud;
	gui.PixelsPerStud = 50;
	gui.LightInfluence = 0; // néon : ignore l'éclairage du monde
	gui.Adornee = part;
	gui.Parent = part;

	const bars: Array<Frame> = [];
	for (let i = 0; i < BAR_COUNT; i++) {
		const bar = new Instance("Frame");
		bar.BorderSizePixel = 0;
		bar.AnchorPoint = new Vector2(0.5, 1);
		bar.Position = UDim2.fromScale((i + 0.5) * SLOT, 1);
		bar.Size = UDim2.fromScale(BAR_WIDTH, MIN_BAR_SCALE);
		bar.BackgroundColor3 = COLOR_LEFT.Lerp(COLOR_RIGHT, i / (BAR_COUNT - 1));

		const corner = new Instance("UICorner");
		corner.CornerRadius = new UDim(0.4, 0);
		corner.Parent = bar;

		bar.Parent = gui;
		bars[i] = bar;
	}
	return { gui, bars };
}

function removePanel(part: BasePart): void {
	const panel = panels.get(part);
	if (!panel) return;
	panel.gui.Destroy();
	panels.delete(part);
}

function addPart(inst: Instance): void {
	if (inst.IsA("BasePart") && !panels.has(inst)) {
		panels.set(inst, buildPanel(inst));
	}
}

// Mappe le spectre linéaire 0..24 kHz en BAR_COUNT bandes log-espacées dans [0,1].
function readBands(target: Array<number>): void {
	const analyzer = MusicController.getBgmAnalyzer();
	const spectrum = analyzer?.GetSpectrum();
	if (spectrum === undefined || spectrum.size() === 0) {
		for (let i = 0; i < BAR_COUNT; i++) target[i] = 0;
		return;
	}
	const bins = spectrum.size();
	const ratio = FREQ_MAX / FREQ_MIN;
	for (let i = 0; i < BAR_COUNT; i++) {
		const fLo = FREQ_MIN * math.pow(ratio, i / BAR_COUNT);
		const fHi = FREQ_MIN * math.pow(ratio, (i + 1) / BAR_COUNT);
		let lo = math.floor((fLo / SAMPLE_RATE_HALF) * bins);
		let hi = math.ceil((fHi / SAMPLE_RATE_HALF) * bins);
		if (lo < 1) lo = 1;
		if (hi > bins) hi = bins;
		if (hi <= lo) hi = lo + 1;
		let sum = 0;
		let count = 0;
		for (let b = lo; b < hi; b++) {
			const v = spectrum[b];
			if (v !== undefined) {
				sum += v;
				count += 1;
			}
		}
		const level = count > 0 ? sum / count : 0;
		target[i] = math.clamp(level * SPECTRUM_SCALE, 0, 1);
	}
}

function step(dt: number): void {
	readBands(bandBuf);
	for (let i = 0; i < BAR_COUNT; i++) {
		const t = bandBuf[i] ?? 0;
		const prev = smoothed[i] ?? 0;
		// attaque instantanée, chute lente
		smoothed[i] = t >= prev ? t : math.max(t, prev - RELEASE_PER_SEC * dt);
	}
	for (const [, panel] of panels) {
		for (let i = 0; i < BAR_COUNT; i++) {
			const h = MIN_BAR_SCALE + (1 - MIN_BAR_SCALE) * (smoothed[i] ?? 0);
			panel.bars[i].Size = UDim2.fromScale(BAR_WIDTH, h);
		}
	}
}

const UPDATE_INTERVAL = 1 / UPDATE_HZ;
let accumulator = 0;

export function init(): void {
	for (const inst of CollectionService.GetTagged(VISUALIZER_TAG)) {
		addPart(inst);
	}
	CollectionService.GetInstanceAddedSignal(VISUALIZER_TAG).Connect((inst) => addPart(inst));
	CollectionService.GetInstanceRemovedSignal(VISUALIZER_TAG).Connect((inst) => {
		if (inst.IsA("BasePart")) removePanel(inst);
	});

	RunService.RenderStepped.Connect((dt) => {
		if (panels.size() === 0) return; // rien à animer -> aucun travail
		accumulator += dt;
		if (accumulator < UPDATE_INTERVAL) return;
		step(accumulator);
		accumulator = 0;
	});
}
```

- [ ] **Step 2 : Compiler**

Run : `npm run build`
Expected : compilation OK, aucune erreur TypeScript.

- [ ] **Step 3 : Commit**

```bash
git add src/client/ui/AudioVisualizer.ts
git commit -m "feat(ui): module AudioVisualizer (spectre BGM, découverte par tag)"
```

---

## Task 5 : Brancher le visualiser dans `main.client.ts`

**Files:**
- Modify: `src/client/main.client.ts`

- [ ] **Step 1 : Ajouter l'import**

Après la ligne `import { MusicController } from "./audio/MusicController";` ajouter :

```ts
import { init as initAudioVisualizer } from "./ui/AudioVisualizer";
```

- [ ] **Step 2 : Ajouter l'init**

Juste après la ligne `MusicController.init();` ajouter :

```ts
initAudioVisualizer();
```

- [ ] **Step 3 : Compiler**

Run : `npm run build`
Expected : compilation OK, aucune erreur.

- [ ] **Step 4 : Commit**

```bash
git add src/client/main.client.ts
git commit -m "feat(client): init du visualiser audio après MusicController"
```

---

## Task 6 : Playtest, réglage et critères d'acceptation

**But :** vérifier le rendu réel, régler `SPECTRUM_SCALE` / `RELEASE_PER_SEC`, valider duplication
et redimensionnement, confirmer absence de latence/freeze.

**Files:** potentiellement `src/client/ui/AudioVisualizer.ts` (ajustement des constantes).

- [ ] **Step 1 : Lancer le playtest**

MCP `start_stop_play` (start). Se rapprocher de la part `AudioVisualizer`. MCP `screen_capture`
pour observer les barres.

- [ ] **Step 2 : Régler l'échelle**

Si les barres saturent (toutes au max) → baisser `SPECTRUM_SCALE`. Si elles bougent à peine →
l'augmenter. (Point de départ déduit des valeurs RMS notées en Task 1.) Si la chute paraît trop
molle/raide, ajuster `RELEASE_PER_SEC`. Rebuild (`npm run build`) + re-playtest après chaque
changement.

- [ ] **Step 3 : Valider la duplication** (la contrainte clé de l'utilisateur)

En cours de playtest, MCP `execute_luau` :

```lua
local CollectionService = game:GetService("CollectionService")
local orig = workspace.Environment.AudioVisualizer
local copy = orig:Clone()
copy.Position = orig.Position + Vector3.new(20, 0, 0)
copy.Parent = orig.Parent
print("CLONE_TAGGED=", CollectionService:HasTag(copy, "AudioVisualizer"))
```
Attendu : la copie affiche des barres animées **sans modification de code** (le tag est cloné, le
signal `GetInstanceAddedSignal` construit son panneau).

- [ ] **Step 4 : Valider le redimensionnement**

MCP `execute_luau` : `workspace.Environment.AudioVisualizer.Size = Vector3.new(24, 6, 0.5)`.
Attendu : les barres se rescalent proprement (layout en Scale), pas de déformation cassée.

- [ ] **Step 5 : Vérifier perf (latence / freeze)**

MCP `get_console_output` (aucune erreur récurrente). Observer la fluidité ; les barres suivent les
beats sans retard perceptible. (Optionnel : ouvrir le MicroProfiler / stats Studio pour confirmer
l'absence de hitch.)

- [ ] **Step 6 : Arrêter + commit si réglages modifiés**

MCP `start_stop_play` (stop).
```bash
git add src/client/ui/AudioVisualizer.ts
git commit -m "tune(ui): échelle/chute du visualiser audio"
```

Critères d'acceptation (cf. spec §9) :
- [ ] BGM normale (playlist, loop, ducking pendant hold, reprise en fin de run).
- [ ] Musique de bouton inchangée.
- [ ] Le(s) panneau(x) dansent au rythme de la BGM, sans latence perceptible.
- [ ] Dupliquer la part (ailleurs) → la copie fonctionne sans toucher au code.
- [ ] Redimensionner la part → barres rescalées proprement.
- [ ] Aucun freeze/hitch introduit.

---

## Task 7 : Mettre à jour `ARCHITECTURE.md`

**Files:**
- Modify: `ARCHITECTURE.md` (§6.10 Audio + nouvelle sous-section)

- [ ] **Step 1 : Mettre à jour §6.10**

Dans la puce BGM de §6.10, remplacer la description « non-3D sound parented to SoundService » par
le fait que la BGM passe désormais par `AudioPlayer` + `AudioDeviceOutput` + `AudioAnalyzer` (reliés
par `Wire`), que le ducking tweene `AudioPlayer.Volume`, et que `MusicController.getBgmAnalyzer()`
expose le spectre. Préciser que la **musique de bouton reste un `Sound` classique**.

- [ ] **Step 2 : Ajouter une sous-section §6.11 Audio Visualizer**

Texte à insérer (adapter la numérotation si besoin) :

```markdown
### 6.11 Audio Visualizer (`client/ui/AudioVisualizer.ts`)
Déco de lobby, 100 % client. Toute part taguée `AudioVisualizer` (CollectionService) reçoit
une `SurfaceGui` + 32 barres (dégradé cyan→violet) construites une seule fois. Une boucle
`RenderStepped` throttlée à ~30 Hz lit `MusicController.getBgmAnalyzer():GetSpectrum()` **une
fois**, regroupe les bins en bandes log-espacées (`getBands`/`readBands`), lisse (attaque
instantanée, chute lente) et écrit la taille (Scale Y) de chaque barre de chaque panneau.
Layout en Scale → la part est redimensionnable/duplicable librement (le tag est cloné).
`GetSpectrum` est client-only ; fallback possible sur `Sound.PlaybackLoudness` via la même
frontière `readBands`.
```

- [ ] **Step 3 : Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: ARCHITECTURE — BGM nouvelle API audio + section visualiser"
```

---

## Self-Review (effectuée à l'écriture du plan)

- **Couverture spec :** §1 obj → Tasks 4/5 ; §2 BGM only → Task 3 ; §3 perf (latence/freeze) →
  garde-fous Tasks 4/6 ; §4.1 tag → Tasks 2/4 ; §4.2 pipeline → Task 3 ; §4.3 module → Task 4 ;
  §4.4 Scale → Task 4 (SLOT/BAR_WIDTH, AnchorPoint) ; §5 Studio → Task 2 ; §6 validation+fallback →
  Task 1 ; §7 fichiers → toutes ; §9 critères → Task 6. Aucun trou.
- **Placeholders :** aucun TBD/TODO ; tout le code est complet.
- **Cohérence des types :** `getBgmAnalyzer(): AudioAnalyzer | undefined` défini en Task 3, utilisé
  en Task 4. `panels: Map<BasePart, Panel>`, `Panel = { gui, bars }`. `readBands(target)` /
  `step(dt)` cohérents. Constantes (`BAR_COUNT`, `SLOT`, `BAR_WIDTH`) définies avant usage.
  Branche fallback : `getBgmSound()` n'est ajouté **que** si Task 1 = NO-GO (sinon `getBgmAnalyzer`).
