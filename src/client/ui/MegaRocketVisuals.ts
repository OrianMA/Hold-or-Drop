import { CollectionService, RunService } from "@rbxts/services";
import { MEGA_ROCKET_PANEL_TAG, MEGA_ROCKET_TAG } from "shared/MegaRocketConfig";

// Arc-en-ciel des Mega Rockets (§6.24) — 100 % présentation, donc 100 % client.
//
// Le serveur se contente de poser le tag MEGA_ROCKET_TAG sur le modèle `Rocket`
// (RocketPlacer) ; ici on passe ses parts en Neon et on fait défiler leur teinte.
// « Ses parts » = TOUT ce qui descend du modèle et est visible : Part, WedgePart,
// MeshPart, UnionOperation (celles-ci ont besoin de UsePartColor, voir addPart).
// Les templates n'ont ni SurfaceAppearance ni TextureID ni Decal, et leurs
// SpecialMesh ont un VertexColor neutre — Color s'applique donc partout.
// Chaque part reçoit un décalage de teinte proportionnel à sa hauteur DANS la
// fusée (mesuré une fois, sur le pad) : le dégradé balaie donc la fusée du bas
// vers le haut au lieu de la faire clignoter d'un bloc.
//
// Le fond du panneau d'événement (MegaRocketFrame, tagué MEGA_ROCKET_PANEL_TAG en
// Studio) porte le même arc-en-ciel, mais en DÉGRADÉ QUI DÉFILE : un UIGradient
// dont la ColorSequence est reconstruite à chaque frame avec la phase courante.
// Un aplat qui change de teinte ne rendrait pas la même chose — c'est le défilement
// qui fait l'effet. Le panneau s'anime en permanence : le compte à rebours est
// toujours affiché.
//
// Une seule connexion RenderStepped, ouverte dès qu'il y a quelque chose à animer
// (panneau OU fusée) et fermée quand il n'y a plus rien (même approche que
// MoneyBurst §6.21). Avec StreamingEnabled seuls les objets à portée existent côté
// client, donc la boucle reste minuscule.

const CYCLE_TIME = 2.5; // secondes pour un tour complet de l'arc-en-ciel
const HUE_PER_STUD = 0.045; // teinte gagnée par stud de hauteur dans la fusée
const UPDATE_INTERVAL = 1 / 20; // 20 Hz — invisible à l'œil, 3× moins de travail
// Luminosité (V du HSV) des couleurs posées. Le Neon brille PROPORTIONNELLEMENT à
// la luminosité de sa couleur : à 1 la fusée est un bloc de lumière blanchi par le
// bloom et les arêtes disparaissent. En dessous de 1 il ne reste qu'un glow coloré
// et la silhouette redevient nette. C'est LE bouton pour doser l'effet.
const NEON_VALUE = 0.7;
// ── Panneau ───────────────────────────────────────────────────────────────────
// Le fond du panneau est une GuiObject, pas du Neon : pas de bloom à contenir, donc
// couleurs pleines (V = 1) comme la référence.
const PANEL_VALUE = 1;
// Durée d'un tour complet du dégradé. Le panneau a sa PROPRE horloge : il défile
// nettement plus vite que la teinte des fusées (CYCLE_TIME), c'est ce qui donne le
// mouvement de bandeau.
const PANEL_CYCLE_TIME = 1.5;
// Points de la ColorSequence étalés sur la largeur (max Roblox : 20). 16 suffit pour
// que le dégradé paraisse continu.
const PANEL_STOPS = 16;
const PANEL_GRADIENT_NAME = "RainbowGradient";

interface MegaRocket {
	// Parts du corps + leur décalage de teinte (fixé au moment de la capture).
	parts: Map<BasePart, number>;
	// Y du pivot au moment de la capture : sert à mesurer la hauteur relative des
	// parts qui arrivent plus tard (streaming).
	baseY: number;
	descendantConn: RBXScriptConnection;
}

const rockets = new Map<Model, MegaRocket>();
// Le dégradé posé sur le fond du compte à rebours
// (Workspace/.../SurfaceGui/MegaRocketFrame).
let panelGradient: UIGradient | undefined;

let stepConn: RBXScriptConnection | undefined;
let elapsed = 0;
let sinceUpdate = 0;

function addPart(entry: MegaRocket, part: BasePart): void {
	// Une part invisible (helpers, colliders) n'a rien à colorer — autant l'exclure
	// de la boucle : les fusées de haut niveau ont plus de 120 parts.
	if (part.Transparency >= 1) return;

	// Une UnionOperation garde par défaut les couleurs des formes qui la composent
	// et IGNORE sa propre propriété Color — sans ça les unions (coque de Lvl1/2/3)
	// resteraient grises au milieu de l'arc-en-ciel.
	if (part.IsA("UnionOperation")) part.UsePartColor = true;

	entry.parts.set(part, (part.Position.Y - entry.baseY) * HUE_PER_STUD);
	part.Material = Enum.Material.Neon;
}

function track(instance: Instance): void {
	if (!instance.IsA("Model") || rockets.has(instance)) return;
	const model = instance;

	const entry: MegaRocket = {
		parts: new Map<BasePart, number>(),
		baseY: model.GetPivot().Position.Y,
		// Les parts peuvent arriver après le tag (réplication / streaming) — on les
		// prend au vol plutôt que de figer la liste à l'instant du tag.
		descendantConn: model.DescendantAdded.Connect((d) => {
			if (d.IsA("BasePart")) addPart(entry, d);
		}),
	};

	for (const d of model.GetDescendants()) {
		if (d.IsA("BasePart")) addPart(entry, d);
	}

	rockets.set(model, entry);
	refreshLoop();
}

function untrack(instance: Instance): void {
	const entry = rockets.get(instance as Model);
	if (!entry) return;
	entry.descendantConn.Disconnect();
	rockets.delete(instance as Model);
	refreshLoop();
}

// Un arc-en-ciel COMPLET étalé sur la largeur, décalé de `phase`. Les teintes
// décroissent de gauche à droite (comme la référence) et le motif couvre pile un
// tour, donc il défile sans couture visible.
function rainbowSequence(phase: number): ColorSequence {
	const stops: ColorSequenceKeypoint[] = [];
	for (let i = 0; i < PANEL_STOPS; i++) {
		const t = i / (PANEL_STOPS - 1);
		// Le modulo de Luau suit le signe du diviseur : (phase - t) % 1 reste positif.
		stops.push(new ColorSequenceKeypoint(t, Color3.fromHSV((phase - t) % 1, 1, PANEL_VALUE)));
	}
	return new ColorSequence(stops);
}

function trackPanel(instance: Instance): void {
	if (!instance.IsA("GuiObject")) return;

	// Le UIGradient MULTIPLIE la couleur de fond : elle doit rester blanche pour que
	// les teintes du dégradé sortent telles quelles.
	instance.BackgroundColor3 = new Color3(1, 1, 1);

	// Créé au besoin plutôt qu'exigé en Studio : c'est de la présentation pure et
	// locale, autant que le panneau survive à une réédition du Frame.
	let gradient = instance.FindFirstChildOfClass("UIGradient");
	if (!gradient) {
		gradient = new Instance("UIGradient");
		gradient.Name = PANEL_GRADIENT_NAME;
		gradient.Parent = instance;
	}
	panelGradient = gradient;
	refreshLoop();
}

function untrackPanel(instance: Instance): void {
	if (panelGradient === undefined || panelGradient.Parent !== instance) return;
	panelGradient = undefined;
	refreshLoop();
}

// Ouvre la boucle dès qu'il y a quelque chose à animer, la ferme sinon.
function refreshLoop(): void {
	if (!rockets.isEmpty() || panelGradient !== undefined) start();
	else stop();
}

function start(): void {
	if (stepConn) return;
	elapsed = 0;
	sinceUpdate = 0;
	stepConn = RunService.RenderStepped.Connect((dt) => {
		elapsed += dt;
		sinceUpdate += dt;
		if (sinceUpdate < UPDATE_INTERVAL) return;
		sinceUpdate = 0;

		const base = elapsed / CYCLE_TIME;

		// Le dégradé du panneau défile sur sa propre horloge, plus rapide.
		if (panelGradient) panelGradient.Color = rainbowSequence(elapsed / PANEL_CYCLE_TIME);

		for (const [, entry] of rockets) {
			for (const [part, offset] of entry.parts) {
				if (!part.Parent) continue; // part détruite (explosion) — ignorée
				part.Color = Color3.fromHSV((base + offset) % 1, 1, NEON_VALUE);
			}
		}
	});
}

function stop(): void {
	if (!stepConn) return;
	stepConn.Disconnect();
	stepConn = undefined;
}

export function init(): void {
	for (const instance of CollectionService.GetTagged(MEGA_ROCKET_TAG)) track(instance);
	CollectionService.GetInstanceAddedSignal(MEGA_ROCKET_TAG).Connect(track);
	CollectionService.GetInstanceRemovedSignal(MEGA_ROCKET_TAG).Connect(untrack);

	for (const instance of CollectionService.GetTagged(MEGA_ROCKET_PANEL_TAG)) trackPanel(instance);
	CollectionService.GetInstanceAddedSignal(MEGA_ROCKET_PANEL_TAG).Connect(trackPanel);
	CollectionService.GetInstanceRemovedSignal(MEGA_ROCKET_PANEL_TAG).Connect(untrackPanel);
}
