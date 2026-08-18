import { ContentProvider, Players, RunService } from "@rbxts/services";

// ── Explosion de billets 2D (particules = ImageLabels) ──────────────────────────
//
// Jouée au claim : une gerbe d'images part du centre, se disperse d'un coup dans
// toutes les directions, freine (drag), puis retombe doucement en tournoyant avant
// de s'effacer. Purement client, purement visuel — aucune interaction, aucun réseau.
//
// Pas de ParticleEmitter ici : c'est de la 2D écran (les billets doivent rester
// lisibles par-dessus le HUD), donc une mini simulation en pixels dans RenderStepped.

const MONEY_IMAGE = "rbxassetid://18209585783";

// ── Tuning ──────────────────────────────────────────────────────────────────────
// Toutes les valeurs en pixels sont exprimées pour un écran de REFERENCE_HEIGHT px
// et remises à l'échelle du viewport réel (mobile compris).
const REFERENCE_HEIGHT = 900;

const PARTICLE_COUNT = 26;
const BILL_SIZE = 70; // px (côté du billet, image carrée mise à l'échelle)
const BILL_SIZE_JITTER = 0.35; // ±35 % de taille pour casser la régularité

const SPEED_MIN = 700; // px/s — vitesse d'éjection initiale
const SPEED_MAX = 1500;
const DRAG = 2.6; // freinage exponentiel /s : l'explosion part fort puis se calme
const GRAVITY = 1500; // px/s² — retombée (vitesse terminale ≈ GRAVITY / DRAG)

const SPIN_MAX = 320; // deg/s de rotation initiale (signe aléatoire)
const SWAY_AMPLITUDE = 90; // px/s² d'oscillation latérale pendant la chute (effet papier)
const SWAY_SPEED_MIN = 2;
const SWAY_SPEED_MAX = 5;

const POP_TIME = 0.1; // s de grossissement 0 → taille pleine au départ
const LIFETIME = 2.6; // s avant destruction
const FADE_START = 1.5; // s avant le début du fondu (le reste = durée du fondu)

const FRAME_NAME = "MoneyBurstBill";

// ── Simulation ──────────────────────────────────────────────────────────────────

interface Bill {
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

const bills: Bill[] = [];
let stepConn: RBXScriptConnection | undefined;

function getScreenGui(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

function destroyBill(index: number): void {
	bills[index].label.Destroy();
	bills.remove(index);
}

function step(dt: number): void {
	// dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les billets.
	const delta = math.min(dt, 1 / 20);

	for (let i = bills.size() - 1; i >= 0; i--) {
		const bill = bills[i];
		bill.age += delta;

		// Freinage exponentiel + gravité : gerbe rapide au départ, chute posée ensuite.
		const damping = math.exp(-DRAG * delta);
		bill.vx *= damping;
		bill.vy = bill.vy * damping + GRAVITY * bill.scale * delta;

		// Balancement latéral façon feuille de papier, seulement une fois le jet freiné.
		bill.swayPhase += bill.swaySpeed * delta;
		bill.vx += math.sin(bill.swayPhase) * SWAY_AMPLITUDE * bill.scale * delta;

		bill.x += bill.vx * delta;
		bill.y += bill.vy * delta;

		bill.spin *= damping;
		bill.rotation += bill.spin * delta;

		const grow = bill.age < POP_TIME ? bill.age / POP_TIME : 1;
		const drawn = bill.size * grow;
		const label = bill.label;
		label.Position = new UDim2(0, bill.x, 0, bill.y);
		label.Size = new UDim2(0, drawn, 0, drawn);
		label.Rotation = bill.rotation;

		if (bill.age > FADE_START) {
			label.ImageTransparency = math.clamp((bill.age - FADE_START) / (LIFETIME - FADE_START), 0, 1);
		}

		if (bill.age >= LIFETIME) destroyBill(i);
	}

	if (bills.isEmpty()) {
		stepConn?.Disconnect();
		stepConn = undefined;
	}
}

// ── API ─────────────────────────────────────────────────────────────────────────

export const MoneyBurst = {
	// Met l'image en cache pour que la toute première explosion de la session ne
	// s'affiche pas en billets vides. À appeler une fois au démarrage du client.
	preload(): void {
		task.spawn(() => {
			const probe = new Instance("ImageLabel");
			probe.Image = MONEY_IMAGE;
			pcall(() => ContentProvider.PreloadAsync([probe]));
			probe.Destroy();
		});
	},

	// Fait exploser une gerbe de billets depuis `origin` (centre de l'écran par défaut).
	play(origin?: Vector2): void {
		const screenGui = getScreenGui();
		if (!screenGui) return;

		const viewport = screenGui.AbsoluteSize;
		if (viewport.X === 0 || viewport.Y === 0) return;

		const scale = viewport.Y / REFERENCE_HEIGHT;
		const center = origin ?? viewport.div(2);

		for (let i = 0; i < PARTICLE_COUNT; i++) {
			// Angles répartis sur le cercle complet + bruit : dispersion "d'un coup"
			// dans toutes les directions, sans trou visible dans la gerbe.
			const angle = ((i + math.random()) / PARTICLE_COUNT) * math.pi * 2;
			const speed = (SPEED_MIN + math.random() * (SPEED_MAX - SPEED_MIN)) * scale;
			const sizeJitter = 1 + (math.random() * 2 - 1) * BILL_SIZE_JITTER;

			const label = new Instance("ImageLabel");
			label.Name = FRAME_NAME;
			label.Image = MONEY_IMAGE;
			label.BackgroundTransparency = 1;
			label.AnchorPoint = new Vector2(0.5, 0.5);
			label.Position = new UDim2(0, center.X, 0, center.Y);
			label.Size = new UDim2(0, 0, 0, 0);
			label.ZIndex = 50;
			label.Active = false;
			label.Parent = screenGui;

			bills.push({
				label,
				x: center.X,
				y: center.Y,
				vx: math.cos(angle) * speed,
				vy: math.sin(angle) * speed,
				size: BILL_SIZE * sizeJitter * scale,
				scale,
				rotation: math.random() * 360,
				spin: (math.random() * 2 - 1) * SPIN_MAX,
				swayPhase: math.random() * math.pi * 2,
				swaySpeed: SWAY_SPEED_MIN + math.random() * (SWAY_SPEED_MAX - SWAY_SPEED_MIN),
				age: 0,
			});
		}

		if (!stepConn) stepConn = RunService.RenderStepped.Connect(step);
	},

	// Retire immédiatement tous les billets encore en vol (fin de partie, rebirth…).
	clear(): void {
		for (const bill of bills) bill.label.Destroy();
		bills.clear();
		stepConn?.Disconnect();
		stepConn = undefined;
	},
};
