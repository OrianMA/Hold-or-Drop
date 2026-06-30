import { RunService, Workspace } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Réaction d'achat dans les tubes néon : à chaque achat au shop, un petit segment
// de couleur file le long des DEUX tubes du joueur, du shop jusqu'au bouton — comme
// si l'amélioration partait physiquement vers le bouton.
//
// Plusieurs achats = plusieurs segments : chaque amélioration lance sa propre
// animation même si d'autres sont déjà en cours, et les achats quasi simultanés sont
// libérés en file avec un petit décalage (QUEUE_DELAY) pour les afficher proprement.
//
// 100 % client / présentation (cf. AudioVisualizer §6.11) : le serveur se contente
// d'incrémenter l'attribut `Pulse` du dossier Environment/NeonPipe/P{n}
// (NeonPipeColors.pulse). On écoute cet attribut et on anime localement — aucune
// couleur n'est répliquée, aucun RemoteEvent.

const ENVIRONMENT = "Environment";
const NEON_PIPE = "NeonPipe";
const PULSE_ATTR = "Pulse";
const TUBE_NAMES = ["Right", "Left"] as const; // les deux tubes par joueur

// Effet d'arrivée au bouton (P{n} → PlayerZones/P{n}/ButtonModel). Le segment qui
// atteint le bouton allume une gerbe d'étincelles + un petit son électrique.
const PLAYER_ZONES = "PlayerZones";
const BUTTON_MODEL = "ButtonModel";
const MOVABLE_MODEL = "MovableModel"; // la particule électrique vit sur la fusée, pas le bouton
const PARTICLE_PART = "ParticleEmmiter"; // nom réel dans Studio (typo conservée volontairement)
const PARTICLE_EMITTER = "UpgradeButtonParticles";
const BUTTON_PART = "ButtonPart";
const PARTICLE_DURATION = 1.2; // s, durée d'émission de la particule à l'arrivée

// Petit sursaut de la fusée à l'arrivée de l'amélioration : la fusée (MovableModel), au
// repos sur son pad, tremble légèrement sur X+Z puis revient à sa place. Réaction visuelle
// à l'upgrade — présentation 100 % client, comme la particule (la fusée n'est jamais en vol
// au moment d'un achat, le joueur étant au shop et non sur son bouton).
const SHAKE_DURATION = 0.4; // s, durée du sursaut (s'amortit jusqu'à 0)
const SHAKE_AMPLITUDE = 0.25; // studs, décalage latéral max (volontairement faible / « soft »)
const SHAKE_FREQUENCY_X = 26; // rad/s, oscillation sur X (~4 Hz)
const SHAKE_FREQUENCY_Z = 19; // rad/s, oscillation sur Z (différente de X → tremblement organique)

// --- réglages -------------------------------------------------------------
const SEGMENT_LENGTH = 5; // longueur du bandeau, en nombre de parts
const TRAVEL_TIME = 5; // s, durée du trajet shop → bouton (assez lent pour voir la couleur passer)
const LIGHT_FACTOR = 0.85; // 0 = couleur du joueur, 1 = blanc pur ; segment très clair / blanc
const TRAIL_FADE = true; // fondu sur la traîne (effet « comète »)
const QUEUE_DELAY = 0.35; // s, décalage entre deux animations enchaînées (file d'attente)
// --------------------------------------------------------------------------

const WHITE = new Color3(1, 1, 1);

// Un segment en vol : sa seule donnée est sa progression 0..1 le long du tube.
interface Segment {
	progress: number;
}

// Un tube physique (Right/Left) : ses parts ordonnées shop → bouton, et les index
// colorés à la frame précédente (pour les restaurer efficacement).
interface PulseTube {
	ordered: BasePart[];
	prevLit: number[];
}

// L'état d'animation d'une salle : les deux tubes, la couleur de base (du slot) et
// sa version claire, la liste des segments en vol (partagée par les deux tubes pour
// rester synchrones), et la file d'attente (pending + minuterie de décalage).
interface RoomState {
	tubes: PulseTube[];
	base: Color3;
	glow: Color3;
	segments: Segment[];
	pending: number;
	sinceRelease: number;
	// Effet d'arrivée au bouton (résolu une fois, peut manquer si le paquet bouton
	// n'a pas encore la particule sur cette salle → effet simplement ignoré).
	particles: ParticleEmitter | undefined;
	sound: Sound | undefined;
	particleToken: number; // dernière arrivée : gère les déclenchements rapprochés
	// Sursaut de la fusée à l'arrivée (résolu une fois ; absent → simplement ignoré).
	movable: Model | undefined;
	shakeTime: number; // temps de sursaut restant (0 = au repos)
	shakeElapsed: number; // temps écoulé du sursaut courant (phase des sinus)
	shakeApplied: Vector3; // décalage de sursaut appliqué (pour le delta / la remise à zéro)
}

const roomStates = new Map<Instance, RoomState>(); // dossier P{n} → état (construit à la 1re impulsion)
const activeRooms = new Set<RoomState>(); // salles en cours d'animation
const lastPulse = new Map<Instance, number>(); // dernière valeur de Pulse vue (pour le delta)
const weightByIndex = new Map<number, number>(); // tampon réutilisé par renderTube (poids max par index)
let shopPosition = Vector3.zero; // référence pour choisir l'extrémité « côté shop »

function lighten(c: Color3): Color3 {
	return c.Lerp(WHITE, LIGHT_FACTOR);
}

// Centroïde des parts du Shop : sert de point de départ à l'ordonnancement.
function computeShopPosition(): Vector3 {
	const shop = Workspace.FindFirstChild("Shop");
	if (shop) {
		let sum = Vector3.zero;
		let count = 0;
		for (const d of shop.GetDescendants()) {
			if (d.IsA("BasePart")) {
				sum = sum.add(d.Position);
				count++;
			}
		}
		if (count > 0) return sum.mul(1 / count);
	}
	warn("NeonPipePulse: Workspace.Shop introuvable, ordonnancement depuis une extrémité arbitraire");
	return Vector3.zero;
}

// Ordonne les parts d'un tube en une chaîne shop → bouton : on démarre par la part
// la plus proche du shop puis on enchaîne le plus proche voisin non visité. Les parts
// sont régulièrement espacées le long d'un chemin continu, donc cette marche reconstruit
// fidèlement le trajet (calcul fait une seule fois par tube, puis mis en cache).
function orderTube(folder: Instance): BasePart[] {
	const parts: BasePart[] = [];
	for (const c of folder.GetChildren()) {
		if (c.IsA("BasePart")) parts.push(c);
	}
	const n = parts.size();
	if (n === 0) return parts;

	let startI = 0;
	let bestD = math.huge;
	for (let i = 0; i < n; i++) {
		const d = parts[i].Position.sub(shopPosition).Magnitude;
		if (d < bestD) {
			bestD = d;
			startI = i;
		}
	}

	const used: boolean[] = [];
	for (let i = 0; i < n; i++) used[i] = false;

	const result: BasePart[] = [];
	let cur = startI;
	used[cur] = true;
	result.push(parts[cur]);
	for (let s = 1; s < n; s++) {
		let bi = -1;
		let bd = math.huge;
		const cp = parts[cur].Position;
		for (let i = 0; i < n; i++) {
			if (used[i]) continue;
			const d = parts[i].Position.sub(cp).Magnitude;
			if (d < bd) {
				bd = d;
				bi = i;
			}
		}
		if (bi < 0) break;
		used[bi] = true;
		result.push(parts[bi]);
		cur = bi;
	}
	return result;
}

// Résout la particule + crée le son 3D du bouton de la salle. Le nom de dossier P{n}
// correspond 1:1 à PlayerZones/P{n}/ButtonModel. Tolère l'absence (effet ignoré).
function resolveButtonEffect(roomName: string): {
	particles: ParticleEmitter | undefined;
	sound: Sound | undefined;
} {
	const room = Workspace.FindFirstChild(PLAYER_ZONES)?.FindFirstChild(roomName);
	if (!room) return { particles: undefined, sound: undefined };

	// La gerbe électrique a été déplacée sur la fusée : MovableModel/ParticleEmmiter/UpgradeButtonParticles.
	const emitter = room
		.FindFirstChild(MOVABLE_MODEL)
		?.FindFirstChild(PARTICLE_PART)
		?.FindFirstChild(PARTICLE_EMITTER);
	const particles = emitter !== undefined && emitter.IsA("ParticleEmitter") ? emitter : undefined;

	// Son électrique 3D : toujours parenté au bouton pour qu'il sonne « sur le bouton ».
	let sound: Sound | undefined;
	const id: string = AudioConfig.sfx.buttonUpgrade.id;
	const buttonPart = room.FindFirstChild(BUTTON_MODEL)?.FindFirstChild(BUTTON_PART);
	if (id !== "" && buttonPart !== undefined && buttonPart.IsA("BasePart")) {
		const s = new Instance("Sound");
		s.Name = "ButtonUpgradeSfx";
		s.SoundId = id;
		s.Volume = AudioConfig.sfx.buttonUpgrade.volume;
		s.Parent = buttonPart;
		sound = s;
	}
	return { particles, sound };
}

// Arrivée d'un segment au bouton : émet la particule PARTICLE_DURATION puis coupe,
// et joue le son. Un token garde la dernière arrivée pour ne pas couper trop tôt
// quand plusieurs segments arrivent coup sur coup.
function fireButtonEffect(state: RoomState): void {
	state.sound?.Play();
	// Sursaut de la fusée : (ré)arme le timer ; advanceShake (boucle) fait le reste.
	if (state.movable) {
		state.shakeTime = SHAKE_DURATION;
		state.shakeElapsed = 0;
	}
	const particles = state.particles;
	if (!particles) return;
	particles.Enabled = true;
	state.particleToken += 1;
	const token = state.particleToken;
	task.delay(PARTICLE_DURATION, () => {
		if (state.particleToken === token) particles.Enabled = false;
	});
}

// Avance le sursaut de la fusée : oscillation X+Z amortie sur SHAKE_DURATION, appliquée
// au MovableModel en delta (la somme revient à zéro → aucune dérive de la position du pad).
function advanceShake(state: RoomState, dt: number): void {
	const movable = state.movable;
	if (!movable) return;

	let target = Vector3.zero;
	if (state.shakeTime > 0) {
		state.shakeElapsed += dt;
		const decay = state.shakeTime / SHAKE_DURATION; // enveloppe 1 → 0 (amortissement)
		target = new Vector3(
			math.sin(state.shakeElapsed * SHAKE_FREQUENCY_X) * SHAKE_AMPLITUDE * decay,
			0,
			math.sin(state.shakeElapsed * SHAKE_FREQUENCY_Z) * SHAKE_AMPLITUDE * decay,
		);
		state.shakeTime -= dt;
	}

	const delta = target.sub(state.shakeApplied);
	if (delta.Magnitude > 1e-4) movable.PivotTo(movable.GetPivot().add(delta));
	state.shakeApplied = target;
}

function buildRoomState(folder: Instance): RoomState | undefined {
	const tubes: PulseTube[] = [];
	for (const name of TUBE_NAMES) {
		const sub = folder.FindFirstChild(name);
		if (!sub) continue;
		const ordered = orderTube(sub);
		if (ordered.size() === 0) continue;
		tubes.push({ ordered, prevLit: [] });
	}
	if (tubes.size() === 0) return undefined;
	const base = tubes[0].ordered[0].Color;
	const effect = resolveButtonEffect(folder.Name);
	const movableInst = Workspace.FindFirstChild(PLAYER_ZONES)
		?.FindFirstChild(folder.Name)
		?.FindFirstChild(MOVABLE_MODEL);
	const movable = movableInst !== undefined && movableInst.IsA("Model") ? movableInst : undefined;
	return {
		tubes,
		base,
		glow: lighten(base),
		segments: [],
		pending: 0,
		sinceRelease: 0,
		particles: effect.particles,
		sound: effect.sound,
		particleToken: 0,
		movable,
		shakeTime: 0,
		shakeElapsed: 0,
		shakeApplied: Vector3.zero,
	};
}

// Met `count` segments en file pour cette salle (un par amélioration achetée).
function triggerRoom(folder: Instance, count: number): void {
	let state = roomStates.get(folder);
	if (!state) {
		state = buildRoomState(folder);
		if (!state) return;
		roomStates.set(folder, state);
	}

	// Nouveau « burst » sur une salle au repos : ré-échantillonne la couleur du slot
	// (les tubes sont à la couleur de base quand rien n'est en cours) et libère le
	// premier segment immédiatement.
	if (state.segments.size() === 0 && state.pending === 0) {
		state.base = state.tubes[0].ordered[0].Color;
		state.glow = lighten(state.base);
		state.sinceRelease = QUEUE_DELAY;
	}

	state.pending += count;
	activeRooms.add(state);
}

// Restaure les parts colorées à la frame précédente puis peint la nouvelle position
// de tous les segments (poids max en cas de chevauchement).
function renderTube(tube: PulseTube, state: RoomState): void {
	for (const idx of tube.prevLit) tube.ordered[idx].Color = state.base;

	weightByIndex.clear();
	const n = tube.ordered.size();
	for (const seg of state.segments) {
		// La tête avance de 0 à n+SEGMENT_LENGTH : le bandeau entre par le shop puis ressort au bouton.
		const head = math.floor(seg.progress * (n + SEGMENT_LENGTH));
		let lo = head - SEGMENT_LENGTH + 1;
		if (lo < 0) lo = 0;
		let hi = head + 1;
		if (hi > n) hi = n;
		for (let i = lo; i < hi; i++) {
			// k = distance à la tête (0 = front, côté bouton) ; la traîne (côté shop) s'estompe.
			const k = hi - 1 - i;
			const w = TRAIL_FADE ? math.max(1 - k / SEGMENT_LENGTH, 0) : 1;
			const prev = weightByIndex.get(i);
			if (prev === undefined || w > prev) weightByIndex.set(i, w);
		}
	}

	const lit: number[] = [];
	for (const [i, w] of weightByIndex) {
		tube.ordered[i].Color = state.base.Lerp(state.glow, w);
		lit.push(i);
	}
	tube.prevLit = lit;
}

function updateRoom(state: RoomState, dt: number): void {
	// Libère les segments en file, décalés de QUEUE_DELAY (file d'attente).
	if (state.pending > 0) {
		state.sinceRelease += dt;
		while (state.pending > 0 && state.sinceRelease >= QUEUE_DELAY) {
			state.segments.push({ progress: 0 });
			state.pending -= 1;
			state.sinceRelease -= QUEUE_DELAY;
		}
	}

	// Avance les segments ; ceux arrivés au bout (>=1) déclenchent l'effet du bouton.
	const live: Segment[] = [];
	for (const seg of state.segments) {
		seg.progress += dt / TRAVEL_TIME;
		if (seg.progress < 1) {
			live.push(seg);
		} else {
			fireButtonEffect(state);
		}
	}
	state.segments = live;

	for (const tube of state.tubes) renderTube(tube, state);

	// Sursaut de la fusée déclenché par une arrivée (peut survivre aux segments).
	advanceShake(state, dt);

	// Plus rien à animer (segments, file, sursaut) → la salle est nettoyée et désactivée.
	const idle =
		state.segments.size() === 0 &&
		state.pending === 0 &&
		state.shakeTime <= 0 &&
		state.shakeApplied.Magnitude < 1e-3;
	if (idle) activeRooms.delete(state);
}

export function init(): void {
	shopPosition = computeShopPosition();

	const root = Workspace.FindFirstChild(ENVIRONMENT)?.FindFirstChild(NEON_PIPE);
	if (!root) {
		warn(`NeonPipePulse: Workspace/${ENVIRONMENT}/${NEON_PIPE} introuvable`);
		return;
	}

	for (const folder of root.GetChildren()) {
		lastPulse.set(folder, (folder.GetAttribute(PULSE_ATTR) as number | undefined) ?? 0);
		// Le delta gère plusieurs achats traités dans la même frame serveur (la
		// réplication d'attribut peut être coalescée : on lit le saut du compteur).
		folder.GetAttributeChangedSignal(PULSE_ATTR).Connect(() => {
			const current = (folder.GetAttribute(PULSE_ATTR) as number | undefined) ?? 0;
			const prev = lastPulse.get(folder) ?? 0;
			lastPulse.set(folder, current);
			const delta = current - prev;
			if (delta > 0) triggerRoom(folder, delta);
		});
	}

	RunService.RenderStepped.Connect((dt) => {
		if (activeRooms.size() === 0) return; // rien à animer → aucun travail
		for (const state of activeRooms) updateRoom(state, dt);
	});
}
