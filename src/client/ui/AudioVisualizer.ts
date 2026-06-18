import { CollectionService, RunService } from "@rbxts/services";
import { MusicController } from "client/audio/MusicController";

// Visualiser de spectre du lobby : des barres d'égaliseur rendues sur chaque part
// taguée VISUALIZER_TAG. Le spectre de la BGM est lu UNE fois par tick puis appliqué
// à tous les panneaux. 100 % client, présentation uniquement.

const VISUALIZER_TAG = "AudioVisualizer";

// --- réglages -------------------------------------------------------------
const BAR_COUNT = 32;
const UPDATE_HZ = 30; // fréquence analyse/rendu (throttlée, pas 60)
const RELEASE_PER_SEC = 2.2; // chute lente ; l'attaque est instantanée
const SPECTRUM_SCALE = 120; // mappe les niveaux RMS -> [0,1] ; semé d'après Task 1, à affiner en Task 6
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
// Indexation 0-based (roblox-ts) : les bins valides vont de 0 à bins-1.
function readBands(target: Array<number>): void {
	const analyzer = MusicController.getBgmAnalyzer();
	const spectrum = analyzer !== undefined ? analyzer.GetSpectrum() : undefined;
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
		let hi = math.floor((fHi / SAMPLE_RATE_HALF) * bins);
		if (lo < 0) lo = 0;
		if (hi > bins) hi = bins;
		if (hi <= lo) hi = math.min(lo + 1, bins);
		let sum = 0;
		for (let b = lo; b < hi; b++) {
			sum += spectrum[b];
		}
		const level = sum / (hi - lo);
		target[i] = math.clamp(level * SPECTRUM_SCALE, 0, 1);
	}
}

function step(dt: number): void {
	readBands(bandBuf);
	for (let i = 0; i < BAR_COUNT; i++) {
		const t = bandBuf[i];
		const prev = smoothed[i];
		// attaque instantanée, chute lente
		smoothed[i] = t >= prev ? t : math.max(t, prev - RELEASE_PER_SEC * dt);
	}
	for (const [, panel] of panels) {
		for (let i = 0; i < BAR_COUNT; i++) {
			const h = MIN_BAR_SCALE + (1 - MIN_BAR_SCALE) * smoothed[i];
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
