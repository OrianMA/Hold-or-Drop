import { Players, RunService, Workspace } from "@rbxts/services";
import { TutorialUI } from "./TutorialUI";

// Le pointage du tutorial. Deux modes :
//   • monde  → une TRAÎNÉE de BillboardGui du joueur jusqu'à la cible, qui s'allument
//              l'une après l'autre (chenillard), plus un chevron de bord d'écran quand
//              la cible est hors champ (sinon le joueur ne sait pas où tourner).
//   • GUI    → une flèche à côté du rectangle de la cible, orientée vers elle.
// Une seule boucle RenderStepped, active uniquement pendant un step qui pointe.

const ARROW_IMAGE = "rbxassetid://104204322044198";

const ARROW_COUNT = 6; // longueur max de la traînée
const MIN_SPACING = 3; // studs minimum entre deux flèches
const ARROW_SIZE = 5; // studs (taille du BillboardGui)
const ARROW_HEIGHT = 3; // studs au-dessus du sol/de la cible
const CHASE_PERIOD = 1.2; // secondes pour un aller de chenillard
const DIM_TRANSPARENCY = 0.75; // flèche "éteinte"

const GUI_ARROW_SIZE = 64; // pixels
const GUI_ARROW_GAP = 12; // pixels entre la flèche et le bord de la cible
const GUI_BOB = 8; // pixels d'oscillation

interface WorldArrow {
	part: Part;
	image: ImageLabel;
}

let worldArrows: WorldArrow[] = [];
let chevron: ImageLabel | undefined;
let guiArrow: ImageLabel | undefined;
let renderConn: RBXScriptConnection | undefined;
let elapsed = 0;

function makeImage(parent: Instance, size: UDim2): ImageLabel {
	const image = new Instance("ImageLabel");
	image.Name = "TutorialArrowImage";
	image.BackgroundTransparency = 1;
	image.Image = ARROW_IMAGE;
	image.Size = size;
	image.AnchorPoint = new Vector2(0.5, 0.5);
	image.Position = new UDim2(0.5, 0, 0.5, 0);
	image.Parent = parent;
	return image;
}

function makeWorldArrow(): WorldArrow {
	// Une part invisible sert d'ancre au BillboardGui (créée côté client : elle n'existe
	// que pour ce joueur).
	const part = new Instance("Part");
	part.Name = "TutorialArrowAnchor";
	part.Size = new Vector3(0.2, 0.2, 0.2);
	part.Transparency = 1;
	part.Anchored = true;
	part.CanCollide = false;
	part.CanQuery = false;
	part.CanTouch = false;
	part.Locked = true;
	part.Parent = Workspace;

	const billboard = new Instance("BillboardGui");
	billboard.Name = "TutorialArrow";
	// Taille en STUDS (offset nul) : la flèche garde sa taille apparente avec la distance.
	billboard.Size = new UDim2(ARROW_SIZE, 0, ARROW_SIZE, 0);
	billboard.AlwaysOnTop = true; // visible même derrière la géométrie de la room
	billboard.LightInfluence = 0; // couleur constante, indépendante de l'éclairage
	billboard.MaxDistance = 500;
	billboard.Adornee = part;
	billboard.Parent = part;

	const image = makeImage(billboard, new UDim2(1, 0, 1, 0));
	image.Visible = false; // Masquées jusqu'à positionnement réel
	return { part, image };
}

function ensureWorldArrows(): void {
	if (worldArrows.size() > 0) return;
	for (let i = 0; i < ARROW_COUNT; i++) worldArrows.push(makeWorldArrow());
}

function ensureChevron(): ImageLabel {
	// `Parent !== undefined` ne suffit PAS : un ScreenGui détruit (TutorialUI.destroy) garde
	// sa hiérarchie interne intacte, juste détachée du DataModel — un chevron qui y est encore
	// parenté a donc toujours un `Parent` non nil. Il faut vérifier qu'il est descendant du
	// ScreenGui COURANT, sinon on continue d'écrire dans une instance orpheline.
	const gui = TutorialUI.ensure();
	if (chevron && chevron.IsDescendantOf(gui)) return chevron;
	chevron = makeImage(gui, new UDim2(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE));
	chevron.Name = "TutorialChevron";
	return chevron;
}

function ensureGuiArrow(): ImageLabel {
	// Même piège que ensureChevron : un ScreenGui détruit garde un `Parent` non nil sur ses
	// anciens enfants, donc on compare explicitement au ScreenGui courant plutôt que de tester
	// juste la présence d'un parent.
	const gui = TutorialUI.ensure();
	if (guiArrow && guiArrow.IsDescendantOf(gui)) return guiArrow;
	guiArrow = makeImage(gui, new UDim2(0, GUI_ARROW_SIZE, 0, GUI_ARROW_SIZE));
	guiArrow.Name = "TutorialGuiArrow";
	return guiArrow;
}

function stopRender(): void {
	if (renderConn) {
		renderConn.Disconnect();
		renderConn = undefined;
	}
}

// Angle (degrés) du vecteur écran `delta`, avec l'image considérée pointant vers le HAUT
// à 0°.
function angleOf(delta: Vector2): number {
	return math.deg(math.atan2(delta.X, -delta.Y));
}

function characterPosition(): Vector3 | undefined {
	const hrp = Players.LocalPlayer.Character?.FindFirstChild("HumanoidRootPart");
	return hrp?.IsA("BasePart") ? hrp.Position : undefined;
}

export const TutorialArrow = {
	// Traînée monde vers `part` + chevron si la cible est hors champ.
	pointAtWorld(part: BasePart): void {
		TutorialArrow.clear();
		ensureWorldArrows();

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			// Le chevron vit dans le ScreenGui du tutorial, qui peut être détruit puis
			// reconstruit pendant que cette boucle tourne : il doit être résolu ICI, à chaque
			// frame, jamais capturé hors boucle — sinon on écrit dans une instance orpheline
			// pendant que le vrai chevron reste invisible.
			const chev = ensureChevron();
			const from = characterPosition();
			const target = part.Position;
			// La caméra doit être lue à chaque frame car elle est nil au spawn
			const camera = Workspace.CurrentCamera;
			if (!from || !camera) {
				// Masquer toutes les flèches si on n'est pas prêt
				for (const arrow of worldArrows) arrow.image.Visible = false;
				chev.Visible = false;
				return;
			}

			// Répartition PROPORTIONNELLE à la distance : selon le step, la cible est entre
			// ~10 studs (bouton) et ~90 studs (boutique), donc un pas fixe est soit trop
			// dense sur les trajets courts, soit trop court sur les longs (la traînée
			// s'arrêterait avant la cible). On calcule combien de flèches tiennent avec un
			// espacement minimum, puis on les étale à pas égal entre le joueur et la cible ;
			// la dernière s'arrête un peu avant la cible plutôt que de se superposer dessus.
			const flat = new Vector3(target.X - from.X, 0, target.Z - from.Z);
			const distance = flat.Magnitude;
			const direction = distance > 0.1 ? flat.Unit : new Vector3(0, 0, 1);
			const phase = (elapsed % CHASE_PERIOD) / CHASE_PERIOD;

			const visibleCount = math.clamp(math.floor(distance / MIN_SPACING), 1, ARROW_COUNT);
			const pitch = distance / (visibleCount + 1);
			// Chenillard calculé sur les flèches VISIBLES uniquement : sur un trajet court
			// (peu de flèches allumées), indexer sur les 6 rangs comptait aussi les flèches
			// masquées et la traînée affichée restait figée en sourdine au lieu de balayer.
			const lit = math.floor(phase * visibleCount);

			for (let i = 0; i < worldArrows.size(); i++) {
				const arrow = worldArrows[i];
				// Au-delà du nombre de flèches visibles pour cette distance → masquée.
				if (i >= visibleCount) {
					arrow.image.Visible = false;
					continue;
				}
				arrow.image.Visible = true;

				const along = pitch * (i + 1);
				const pos = from.add(direction.mul(along)).add(new Vector3(0, ARROW_HEIGHT, 0));
				arrow.part.Position = pos;

				// Chenillard : la flèche dont le rang correspond à la phase est pleine, les
				// autres sont estompées.
				arrow.image.ImageTransparency = i === lit ? 0 : DIM_TRANSPARENCY;

				// Orientation écran : vers la flèche suivante (ou vers la cible pour la
				// dernière visible).
				const isLast = i === visibleCount - 1;
				const nextWorld = isLast
					? target
					: from.add(direction.mul(pitch * (i + 2))).add(new Vector3(0, ARROW_HEIGHT, 0));
				const [here] = camera.WorldToViewportPoint(pos);
				const [nextPoint] = camera.WorldToViewportPoint(nextWorld);
				arrow.image.Rotation = angleOf(new Vector2(nextPoint.X - here.X, nextPoint.Y - here.Y));
			}

			// Chevron de bord d'écran quand la cible n'est pas visible.
			const [screen, onScreen] = camera.WorldToViewportPoint(target);
			if (onScreen) {
				chev.Visible = false;
			} else {
				const viewport = camera.ViewportSize;
				const center = viewport.mul(0.5);
				// Z < 0 : la cible est DERRIÈRE la caméra, et WorldToViewportPoint renvoie alors des
				// coordonnées écran en MIROIR — il faut inverser le vecteur, sinon le chevron indique
				// exactement le mauvais côté (le cas même pour lequel il existe).
				let toTarget = new Vector2(screen.X - center.X, screen.Y - center.Y);
				if (screen.Z < 0) {
					toTarget = toTarget.mul(-1);
				}
				const dir = toTarget.Magnitude > 1 ? toTarget.Unit : new Vector2(0, -1);
				const margin = GUI_ARROW_SIZE;
				const clamped = center.add(
					new Vector2(
						math.clamp(dir.X * viewport.X, -center.X + margin, center.X - margin),
						math.clamp(dir.Y * viewport.Y, -center.Y + margin, center.Y - margin),
					),
				);
				chev.Visible = true;
				chev.Position = new UDim2(0, clamped.X, 0, clamped.Y);
				chev.ImageTransparency = 0;
				chev.Rotation = angleOf(dir);
			}
		});
	},

	// Flèche écran posée à gauche du rectangle de la cible, pointant vers elle.
	pointAtGui(target: GuiObject): void {
		TutorialArrow.clear();

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			// Même piège que le chevron : cette flèche vit dans le ScreenGui du tutorial, qui
			// peut être détruit puis reconstruit pendant que la boucle tourne. On la résout ICI,
			// à chaque frame, plutôt que de la capturer hors boucle.
			const arrow = ensureGuiArrow();
			arrow.Visible = true;
			const pos = target.AbsolutePosition;
			const size = target.AbsoluteSize;
			const bob = math.sin(elapsed * 4) * GUI_BOB;
			// À gauche du bord gauche, centrée verticalement, pointant vers la droite (90°).
			arrow.Position = new UDim2(
				0,
				pos.X - GUI_ARROW_GAP - GUI_ARROW_SIZE / 2 + bob,
				0,
				pos.Y + size.Y / 2,
			);
			arrow.Rotation = 90;
		});
	},

	clear(): void {
		stopRender();
		elapsed = 0;
		for (const arrow of worldArrows) arrow.part.Destroy();
		worldArrows = [];
		if (chevron) {
			chevron.Destroy();
			chevron = undefined;
		}
		if (guiArrow) {
			guiArrow.Destroy();
			guiArrow = undefined;
		}
	},
};
