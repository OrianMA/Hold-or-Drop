import { ContentProvider, Players, RunService } from "@rbxts/services";

// ── Petite pluie d'icônes 2D (particules = ImageLabels) ─────────────────────────
//
// Jouée en même temps que le flash doré "CRITICAL CLAIM" (ClaimFlashText) : une
// poignée d'images tombent du haut de l'écran, dérivent en tournant doucement et
// se dissolvent en bas. Purement client, purement visuel.
//
// `play`/`preload` acceptent une IMAGE : la même simulation sert aussi la pluie
// jouée à l'accomplissement d'une quête (§6.26), qui doit être exactement le même
// effet avec une autre icône. Sans argument, c'est l'icône du Critical Claim.
//
// Même approche que MoneyBurst : pas de ParticleEmitter, c'est de la 2D écran, donc
// une mini simulation en pixels dans RenderStepped.

// Icône dorée du Critical Claim. Exportée : l'escalade de paiement (PayoutTiers,
// §6.4) s'en sert pour sa pluie d'or, et il ne doit y avoir qu'une source de vérité.
export const RAIN_IMAGE = "rbxassetid://13506500866";

// ── Tuning ──────────────────────────────────────────────────────────────────────
// Les valeurs en pixels sont exprimées pour un écran de REFERENCE_HEIGHT px et
// remises à l'échelle du viewport réel (mobile compris).
const REFERENCE_HEIGHT = 900;

const PARTICLE_COUNT = 40; // pluie fournie, mais on doit encore voir passer les icônes, pas un rideau
const ICON_SIZE = 60; // px (image carrée mise à l'échelle)
const ICON_SIZE_JITTER = 0.3; // ±30 % de taille pour casser la régularité

// Plafond de gouttes VIVANTES, tous appels confondus. L'escalade de paiement
// (PayoutTiers, §6.4) empile jusqu'à trois pluies en une seconde : sans ce garde-fou
// on ferait tomber 150+ ImageLabels simulés par frame sur mobile.
const MAX_LIVE_DROPS = 70;

// Les icônes ne sont pas lâchées par un timer : elles démarrent réparties dans une
// bande AU-DESSUS de l'écran, donc elles entrent dans le champ les unes après les
// autres — c'est ce qui fait la pluie plutôt qu'une salve.
// C'est aussi ce qui règle la DURÉE de la pluie : plus la bande est haute, plus les
// dernières icônes entrent tard dans le champ.
const SPAWN_BAND = 1600; // px de hauteur de la bande de départ, au-dessus du bord haut

const FALL_SPEED_MIN = 340; // px/s
const FALL_SPEED_MAX = 620;
const GRAVITY = 300; // px/s² — la chute s'accélère légèrement
const DRIFT_MAX = 70; // px/s de dérive horizontale initiale (signe aléatoire)

const SPIN_MAX = 110; // deg/s de rotation (signe aléatoire)
const SWAY_AMPLITUDE = 55; // px/s² d'oscillation latérale (effet feuille)
const SWAY_SPEED_MIN = 1.5;
const SWAY_SPEED_MAX = 3.5;

const FADE_START_Y = 0.68; // fraction de hauteur d'écran où l'icône commence à se dissoudre
const MAX_LIFETIME = 9; // s — garde-fou si une icône ne sort jamais du champ

const LABEL_NAME = "CriticalRainIcon";
const Z_INDEX = 55; // au-dessus du HUD et de la gerbe de billets, SOUS le texte du flash (60)

// ── Simulation ──────────────────────────────────────────────────────────────────

interface Drop {
	label: ImageLabel;
	x: number; // px, coordonnées écran
	y: number;
	vx: number;
	vy: number;
	size: number; // px (taille pleine, après jitter)
	scale: number; // facteur viewport, appliqué à la gravité et au balancement
	rotation: number; // deg
	spin: number; // deg/s
	swayPhase: number;
	swaySpeed: number;
	age: number;
}

const drops: Drop[] = [];
let stepConn: RBXScriptConnection | undefined;

function getScreenGui(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

function destroyDrop(index: number): void {
	drops[index].label.Destroy();
	drops.remove(index);
}

function step(dt: number): void {
	// dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les icônes.
	const delta = math.min(dt, 1 / 20);

	const screenGui = getScreenGui();
	const viewportHeight = screenGui !== undefined ? screenGui.AbsoluteSize.Y : 0;

	for (let i = drops.size() - 1; i >= 0; i--) {
		const drop = drops[i];
		drop.age += delta;

		drop.vy += GRAVITY * drop.scale * delta;

		// Balancement latéral façon feuille qui tombe.
		drop.swayPhase += drop.swaySpeed * delta;
		drop.vx += math.sin(drop.swayPhase) * SWAY_AMPLITUDE * drop.scale * delta;

		drop.x += drop.vx * delta;
		drop.y += drop.vy * delta;
		drop.rotation += drop.spin * delta;

		const label = drop.label;
		label.Position = new UDim2(0, drop.x, 0, drop.y);
		label.Rotation = drop.rotation;

		// Dissolution dans le bas de l'écran : l'icône ne disparaît jamais d'un coup.
		if (viewportHeight > 0) {
			const fadeFrom = viewportHeight * FADE_START_Y;
			if (drop.y > fadeFrom) {
				label.ImageTransparency = math.clamp((drop.y - fadeFrom) / (viewportHeight - fadeFrom), 0, 1);
			}
		}

		const belowScreen = viewportHeight > 0 && drop.y > viewportHeight + drop.size;
		if (belowScreen || drop.age >= MAX_LIFETIME) destroyDrop(i);
	}

	if (drops.isEmpty()) {
		stepConn?.Disconnect();
		stepConn = undefined;
	}
}

// ── API ─────────────────────────────────────────────────────────────────────────

export interface RainOptions {
	count?: number; // nombre de gouttes (défaut PARTICLE_COUNT)
	band?: number; // hauteur de la bande de départ en px (défaut SPAWN_BAND)
	// Plan de rendu. Défaut Z_INDEX (55) = par-dessus le HUD, pour le flash de claim.
	// L'écran de fin passe une valeur BASSE : la pluie tombe DERRIÈRE le montant, qui
	// reste lisible (ButtonFinishGame et BaseCashText sont en ZIndex 1).
	zIndex?: number;
}

export const CriticalRain = {
	// Met l'image en cache pour que la première pluie de la session ne s'affiche pas
	// vide. À appeler une fois au démarrage du client.
	preload(image = RAIN_IMAGE): void {
		task.spawn(() => {
			const probe = new Instance("ImageLabel");
			probe.Image = image;
			pcall(() => ContentProvider.PreloadAsync([probe]));
			probe.Destroy();
		});
	},

	// Lâche la pluie. Rejouable : les gouttes en vol continuent leur chute.
	//
	// `options.count` règle la densité (défaut PARTICLE_COUNT) et `options.band` la
	// hauteur de la bande de départ, donc la DURÉE de la pluie : une bande courte fait
	// une vague qui passe, une bande haute une averse qui traîne.
	play(image = RAIN_IMAGE, options?: RainOptions): void {
		const screenGui = getScreenGui();
		if (!screenGui) return;

		const viewport = screenGui.AbsoluteSize;
		if (viewport.X === 0 || viewport.Y === 0) return;

		const scale = viewport.Y / REFERENCE_HEIGHT;
		const band = options?.band ?? SPAWN_BAND;
		const zIndex = options?.zIndex ?? Z_INDEX;
		// Le plafond ÉVICTE les plus anciennes gouttes plutôt que de tronquer la
		// nouvelle pluie : pendant l'escalade de paiement, c'est toujours le DERNIER
		// palier (le plus gros) qui doit s'afficher en entier — tronquer ferait
		// décroître l'effet à mesure que le gain grossit, exactement l'inverse du but.
		const count = math.min(options?.count ?? PARTICLE_COUNT, MAX_LIVE_DROPS);
		if (count <= 0) return;
		const overflow = drops.size() + count - MAX_LIVE_DROPS;
		for (let i = 0; i < overflow; i++) destroyDrop(0);

		for (let i = 0; i < count; i++) {
			const sizeJitter = 1 + (math.random() * 2 - 1) * ICON_SIZE_JITTER;
			const size = ICON_SIZE * sizeJitter * scale;
			// X réparti en colonnes + bruit : la pluie couvre la largeur sans paquets.
			const x = ((i + math.random()) / count) * viewport.X;
			const y = -size - math.random() * band * scale;

			const label = new Instance("ImageLabel");
			label.Name = LABEL_NAME;
			label.Image = image;
			label.BackgroundTransparency = 1;
			label.AnchorPoint = new Vector2(0.5, 0.5);
			label.Position = new UDim2(0, x, 0, y);
			label.Size = new UDim2(0, size, 0, size);
			label.Rotation = math.random() * 360;
			label.ZIndex = zIndex;
			label.Active = false;
			label.Parent = screenGui;

			drops.push({
				label,
				x,
				y,
				vx: (math.random() * 2 - 1) * DRIFT_MAX * scale,
				vy: (FALL_SPEED_MIN + math.random() * (FALL_SPEED_MAX - FALL_SPEED_MIN)) * scale,
				size,
				scale,
				rotation: label.Rotation,
				spin: (math.random() * 2 - 1) * SPIN_MAX,
				swayPhase: math.random() * math.pi * 2,
				swaySpeed: SWAY_SPEED_MIN + math.random() * (SWAY_SPEED_MAX - SWAY_SPEED_MIN),
				age: 0,
			});
		}

		if (!stepConn) stepConn = RunService.RenderStepped.Connect(step);
	},

	// Retire immédiatement toutes les icônes encore en vol (fin de partie, rebirth…).
	clear(): void {
		for (const drop of drops) drop.label.Destroy();
		drops.clear();
		stepConn?.Disconnect();
		stepConn = undefined;
	},
};
