import { ContentProvider, Players, RunService } from "@rbxts/services";
import { playBillPop } from "client/audio/CashSound";

// ── Explosion de billets 2D (particules = ImageLabels) ──────────────────────────
//
// Jouée au claim : une gerbe d'images part du centre, se disperse d'un coup dans
// toutes les directions, freine (drag), puis retombe doucement en tournoyant avant
// de s'effacer. Purement client, purement visuel — aucune interaction, aucun réseau.
//
// Pas de ParticleEmitter ici : c'est de la 2D écran (les billets doivent rester
// lisibles par-dessus le HUD), donc une mini simulation en pixels dans RenderStepped.

// Image du billet. Exportée : l'escalade de paiement (PayoutTiers, §6.4) s'en sert
// pour sa pluie de billets, et il ne doit y avoir qu'une source de vérité.
export const MONEY_IMAGE = "rbxassetid://18209585783";

// ── Tuning ──────────────────────────────────────────────────────────────────────
// Toutes les valeurs en pixels sont exprimées pour un écran de REFERENCE_HEIGHT px
// et remises à l'échelle du viewport réel (mobile compris).
const REFERENCE_HEIGHT = 900;

const PARTICLE_COUNT = 26;

// Plafond de billets VIVANTS, tous appels confondus. L'escalade de paiement
// (PayoutTiers, §6.4) empile jusqu'à trois gerbes en une seconde : sans ce garde-fou
// on simulerait 100+ ImageLabels par frame sur mobile.
const MAX_LIVE_BILLS = 60;

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

// ── Variante "aspiration" (récompense journalière) ──────────────────────────────
// Même explosion, mais au lieu de retomber et de s'effacer, les billets sont aspirés
// vers une cible (le compteur d'argent du HUD). Le vol est accéléré (p²) : ils
// décollent mollement puis filent dans le compteur, ce qui lit comme une aspiration
// plutôt qu'un déplacement linéaire.
const GATHER_TIME = 0.75; // s de vol vers la cible
// Les billets ne basculent PAS tous en même temps : le départ de l'aspiration est
// échelonné sur GATHER_SPREAD dans l'ordre d'émission (donc en vague autour du
// cercle), plus un petit bruit pour que ça ne soit pas mécanique.
const GATHER_SPREAD = 0.25;
const GATHER_JITTER = 0.05;
// Temps de FREINAGE entre la fin de l'explosion et le départ vers la cible. Le billet
// n'est pas gelé d'un coup : sa vitesse (translation ET rotation) est multipliée par
// une courbe qui vaut 1 à l'entrée et 0 à la sortie, dérivée nulle aux deux bouts. Il
// finit donc immobile — la pause est bien là — mais en y arrivant en glissant.
const GATHER_BRAKE = 0.2;
// Orientation prise pendant le vol : le billet cesse de tournoyer et se remet droit.
const GATHER_END_ROTATION = 0;
const GATHER_END_SCALE = 0.25; // taille à l'arrivée, en fraction de la taille pleine
const GATHER_FADE_FROM = 0.8; // fraction du vol après laquelle le billet s'efface

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
	// Aspiration (optionnelle) : à `gatherAt` secondes, le billet quitte la simulation
	// balistique et rejoint `target` en GATHER_TIME. `target` est résolu au moment du
	// départ, pas à l'explosion — le HUD peut être masqué au lancement de la gerbe.
	gatherAt?: number;
	resolveTarget?: () => Vector2 | undefined;
	gathering?: {
		fromX: number; // position gelée pendant l'arrêt, origine de la ligne droite
		fromY: number;
		toX: number;
		toY: number;
		rotationFrom: number; // rotation au moment du gel, ramenée à GATHER_END_ROTATION
		elapsed: number; // s depuis le gel (arrêt + vol)
	};
}

export interface MoneyBurstOptions {
	// Position ABSOLUE (écran) vers laquelle les billets convergent — typiquement le
	// centre du compteur d'argent. Omise, les billets retombent et s'effacent.
	gatherTo?: () => Vector2 | undefined;
	// Délai avant le départ de l'aspiration (défaut : GATHER_DELAY).
	gatherAfter?: number;
	// Nombre de billets (défaut : PARTICLE_COUNT). C'est ce qui fait grossir la gerbe
	// palier après palier pendant le paiement.
	count?: number;
}

// s de lévitation (explosion libre) avant que l'aspiration ne commence.
const GATHER_DELAY = 0.55;

const bills: Bill[] = [];
let stepConn: RBXScriptConnection | undefined;

function getScreenGui(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

// Interpolation douce (3t²−2t³) : dérivée nulle aux deux bouts, donc aucune cassure
// visible quand un régime prend le relais de l'autre.
function smoothstep(t: number): number {
	const c = math.clamp(t, 0, 1);
	return c * c * (3 - 2 * c);
}

// Écart d'angle le plus court (−180..180) : le billet retrouve son orientation de
// départ par le chemin le plus court, jamais en refaisant un tour complet.
function shortestAngle(from: number, to: number): number {
	return (((to - from + 180) % 360) + 360) % 360 - 180;
}

function destroyBill(index: number): void {
	bills[index].label.Destroy();
	bills.remove(index);
}

function step(dt: number): void {
	// dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les billets.
	const delta = math.min(dt, 1 / 20);

	// Origine du ScreenGui : les billets sont positionnés en offsets LOCAUX, alors que
	// la cible d'aspiration est donnée en coordonnées écran absolues.
	const origin = getScreenGui()?.AbsolutePosition ?? new Vector2(0, 0);

	for (let i = bills.size() - 1; i >= 0; i--) {
		const bill = bills[i];
		bill.age += delta;
		const label = bill.label;

		// ── Aspiration : arrêt net, puis ligne droite vers la cible ───────────────
		if (bill.gatherAt !== undefined && bill.age >= bill.gatherAt) {
			if (!bill.gathering) {
				const target = bill.resolveTarget?.();
				if (!target) {
					// Pas de cible (HUD absent) → on repasse en fondu normal plutôt que
					// de laisser le billet figé en l'air.
					bill.gatherAt = undefined;
				} else {
					// Point d'entrée du freinage. fromX/fromY/rotationFrom sont réécrits à
					// chaque image tant que le billet glisse encore, pour que la ligne
					// droite parte de son point d'arrêt RÉEL.
					bill.gathering = {
						fromX: bill.x,
						fromY: bill.y,
						toX: target.X - origin.X,
						toY: target.Y - origin.Y,
						rotationFrom: bill.rotation,
						elapsed: 0,
					};
				}
			}

			const gathering = bill.gathering;
			if (gathering) {
				gathering.elapsed += delta;

				// 1. Freinage : le billet continue sur sa lancée en ralentissant jusqu'à
				//    l'arrêt. La vitesse est CONTINUE de part et d'autre — à l'entrée elle
				//    vaut encore celle de l'explosion, à la sortie exactement zéro — donc
				//    aucune cassure visible. La gravité ne s'applique plus ici, sinon le
				//    billet ne s'immobiliserait jamais.
				if (gathering.elapsed < GATHER_BRAKE) {
					const brake = 1 - smoothstep(gathering.elapsed / GATHER_BRAKE);
					bill.x += bill.vx * brake * delta;
					bill.y += bill.vy * brake * delta;
					bill.rotation += bill.spin * brake * delta;

					gathering.fromX = bill.x;
					gathering.fromY = bill.y;
					gathering.rotationFrom = bill.rotation;

					label.Position = new UDim2(0, bill.x, 0, bill.y);
					label.Rotation = bill.rotation;
					continue;
				}

				// 2. Vol en ligne droite, easing p². Sa dérivée est nulle en p = 0 : le
				//    départ se fait donc à vitesse nulle, dans la continuité exacte du
				//    freinage — puis ça accélère jusqu'à l'arrivée.
				const p = math.clamp((gathering.elapsed - GATHER_BRAKE) / GATHER_TIME, 0, 1);
				const eased = p * p;

				const drawX = gathering.fromX + (gathering.toX - gathering.fromX) * eased;
				const drawY = gathering.fromY + (gathering.toY - gathering.fromY) * eased;

				// Le billet se remet droit pendant le vol, par le chemin angulaire le
				// plus court : il arrive à plat dans le compteur, sans tournoyer.
				const settle = smoothstep(p);
				const rotation =
					gathering.rotationFrom +
					shortestAngle(gathering.rotationFrom, GATHER_END_ROTATION) * settle;

				const drawn = bill.size * (1 - (1 - GATHER_END_SCALE) * eased);
				label.Position = new UDim2(0, drawX, 0, drawY);
				label.Size = new UDim2(0, drawn, 0, drawn);
				label.Rotation = rotation;
				label.ImageTransparency =
					p > GATHER_FADE_FROM ? (p - GATHER_FADE_FROM) / (1 - GATHER_FADE_FROM) : 0;

				if (p >= 1) {
					playBillPop(); // petit "pop" à chaque billet encaissé
					destroyBill(i);
				}
				continue;
			}
		}

		// ── Explosion : freinage exponentiel + gravité ────────────────────────────
		// Gerbe rapide au départ, chute posée ensuite.
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
	// Avec `options.gatherTo`, les billets ne retombent pas : après une seconde
	// d'explosion libre ils sont aspirés vers la cible (le compteur d'argent du HUD).
	play(origin?: Vector2, options?: MoneyBurstOptions): void {
		const screenGui = getScreenGui();
		if (!screenGui) return;

		const viewport = screenGui.AbsoluteSize;
		if (viewport.X === 0 || viewport.Y === 0) return;

		const scale = viewport.Y / REFERENCE_HEIGHT;
		const center = origin ?? viewport.div(2);

		// Le plafond ÉVICTE les plus anciens billets plutôt que de tronquer la nouvelle
		// gerbe : pendant l'escalade de paiement, c'est toujours le DERNIER palier (le
		// plus gros) qui doit s'afficher en entier.
		const count = math.min(options?.count ?? PARTICLE_COUNT, MAX_LIVE_BILLS);
		if (count <= 0) return;
		const overflow = bills.size() + count - MAX_LIVE_BILLS;
		for (let i = 0; i < overflow; i++) destroyBill(0);

		for (let i = 0; i < count; i++) {
			// Angles répartis sur le cercle complet + bruit : dispersion "d'un coup"
			// dans toutes les directions, sans trou visible dans la gerbe.
			const angle = ((i + math.random()) / count) * math.pi * 2;
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
				// Départs étalés dans l'ordre d'émission (donc en vague autour du cercle)
				// plutôt qu'au hasard : les billets ne basculent pas tous ensemble, et
				// l'arrivée dans le compteur se fait en rafale au lieu d'un seul paquet.
				gatherAt: options?.gatherTo
					? (options.gatherAfter ?? GATHER_DELAY) +
						(i / count) * GATHER_SPREAD +
						math.random() * GATHER_JITTER
					: undefined,
				resolveTarget: options?.gatherTo,
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
