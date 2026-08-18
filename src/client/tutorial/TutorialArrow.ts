import { Players, RunService, Workspace } from "@rbxts/services";
import { TutorialUI, Z_ARROW } from "./TutorialUI";

// Le pointage du tutorial. Deux modes :
//   • monde  → un RUBAN tendu des pieds du joueur JUSQU'À la cible : UNE seule part plate
//              dont un SurfaceGui tuile le chevron à taille fixe. Le ruban s'allonge ou se
//              rétracte avec la distance, les chevrons ne se déforment jamais, ils défilent
//              vers la cible. Il est tendu en 3D, pas à l'horizontale : son extrémité reste
//              posée sur l'objet, donc il plonge quand la cible est plus bas (saut) et monte
//              quand elle est plus haut. Plus un chevron de bord d'écran quand la cible est
//              hors champ (sinon le joueur ne sait pas où tourner).
//   • GUI    → une flèche à côté du rectangle de la cible, orientée vers elle.
// Une seule boucle RenderStepped, active uniquement pendant un step qui pointe.

const ARROW_IMAGE = "rbxassetid://104204322044198";

// --- Ruban monde ------------------------------------------------------------------
const TRAIL_WIDTH = 3.5; // studs — largeur du ruban
const TRAIL_TILE = 4; // studs — longueur d'UN chevron (fixe, indépendante de la distance)
const TRAIL_PIXELS_PER_STUD = 24; // résolution du SurfaceGui
const TRAIL_THICKNESS = 0.2; // studs — épaisseur de la part support (invisible)
const TRAIL_START_OFFSET = 0; // studs au-dessus du HumanoidRootPart (≈ le torse) où démarre le ruban
const TARGET_GROUND_PROBE = 60; // studs — profondeur de la sonde qui cherche le sol sous la cible
const TARGET_GROUND_LIFT = 1.7; // studs — le ruban s'arrête juste au-dessus de ce sol
const TRAIL_MIN_LENGTH = 3; // studs — en deçà on masque : le joueur est arrivé
const SCROLL_PERIOD = 0.6; // secondes pour avancer d'un chevron

const TILE_PIXELS = TRAIL_TILE * TRAIL_PIXELS_PER_STUD;

// --- Flèches écran ----------------------------------------------------------------
const GUI_ARROW_SIZE = 64; // pixels
const GUI_ARROW_GAP = 12; // pixels entre la flèche et le bord de la cible
const GUI_BOB = 8; // pixels d'oscillation

interface Trail {
	part: Part;
	surface: SurfaceGui;
	image: ImageLabel;
}

let trail: Trail | undefined;
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
	image.ZIndex = Z_ARROW;
	image.Parent = parent;
	return image;
}

function makeTrail(): Trail {
	// Part support créée côté CLIENT : elle n'existe que pour ce joueur, donc aucune
	// réplication ni gestion par joueur côté serveur.
	const part = new Instance("Part");
	part.Name = "TutorialTrail";
	// Repère LOCAL de la plaque : X = largeur, Y = longueur, Z = épaisseur. Elle est ensuite
	// couchée à plat par son CFrame (voir layoutTrail).
	part.Size = new Vector3(TRAIL_WIDTH, 1, TRAIL_THICKNESS);
	part.Transparency = 1; // seul le SurfaceGui se voit
	part.Anchored = true;
	part.CanCollide = false;
	part.CanQuery = false;
	part.CanTouch = false;
	part.CastShadow = false;
	part.Locked = true;
	part.Parent = Workspace;

	const surface = new Instance("SurfaceGui");
	surface.Name = "TutorialTrailSurface";
	// Face FRONT, pas Top : c'est la seule face dont l'orientation du GUI est garantie
	// (haut du GUI = +Y de la part, jamais tournée ni miroir). Sur la face Top les axes du
	// GUI sont transposés (X du GUI = Z de la part) — mesuré en Studio. On couche donc la
	// plaque pour que sa face avant regarde le ciel et que son +Y vise la cible : la flèche,
	// dessinée pointe en haut, pointe alors vers la cible sans hypothèse à vérifier.
	surface.Face = Enum.NormalId.Front;
	// PixelsPerStud FIXE : c'est ce qui garantit qu'un chevron mesure toujours TRAIL_TILE
	// studs, que le ruban fasse 10 ou 90 studs de long. Seul leur NOMBRE change.
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud;
	surface.PixelsPerStud = TRAIL_PIXELS_PER_STUD;
	// Pas d'AlwaysOnTop : le ruban se fait masquer par le décor comme n'importe quel objet.
	surface.LightInfluence = 0;
	surface.Adornee = part;
	surface.Parent = part;

	// L'image déborde d'une tuile pour pouvoir défiler sans laisser de trou : ce cadre la
	// recoupe aux dimensions exactes du ruban.
	const clip = new Instance("Frame");
	clip.Name = "TrailClip";
	clip.Size = new UDim2(1, 0, 1, 0);
	clip.BackgroundTransparency = 1;
	clip.ClipsDescendants = true;
	clip.Parent = surface;

	const image = new Instance("ImageLabel");
	image.Name = "TrailImage";
	image.Image = ARROW_IMAGE;
	image.BackgroundTransparency = 1;
	image.ScaleType = Enum.ScaleType.Tile;
	// Largeur : toute la largeur du ruban. Hauteur : une longueur FIXE en pixels, donc en
	// studs (PixelsPerStud constant) — la tuile ne s'étire jamais.
	image.TileSize = new UDim2(1, 0, 0, TILE_PIXELS);
	image.Size = new UDim2(1, 0, 1, TILE_PIXELS);
	image.Position = new UDim2(0, 0, 0, 0);
	image.Parent = clip;

	return { part, surface, image };
}

function ensureTrail(): Trail {
	if (trail && trail.part.Parent !== undefined) return trail;
	trail = makeTrail();
	return trail;
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

function characterRoot(): BasePart | undefined {
	const hrp = Players.LocalPlayer.Character?.FindFirstChild("HumanoidRootPart");
	return hrp?.IsA("BasePart") ? hrp : undefined;
}

const groundParams = new RaycastParams();
groundParams.FilterType = Enum.RaycastFilterType.Exclude;

// Le groupe auquel appartient la cible : son Model s'il y en a un (ButtonModel), sinon son
// dossier (Shop). Jamais le Workspace, ce qui reviendrait à exclure la scène entière.
function targetGroup(part: BasePart): Instance {
	const model = part.FindFirstAncestorOfClass("Model");
	if (model) return model;
	const parent = part.Parent;
	return parent !== undefined && parent !== Workspace ? parent : part;
}

// Point visé : le SOL sous la cible, pas son centre — le ruban finit donc presque à plat
// au pied de l'objet au lieu de s'arrêter en l'air à mi-hauteur. On part du dessous de la
// cible et on sonde vers le bas. La demi-hauteur est mesurée dans le repère du MONDE — les
// trois axes de la part projetés sur Y — et non via Size.Y, qui ne serait la verticale que
// si la cible n'était pas tournée.
function targetAimPoint(part: BasePart): Vector3 {
	const cf = part.CFrame;
	const size = part.Size;
	const halfHeight =
		0.5 * (math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z);
	const base = part.Position.sub(new Vector3(0, halfHeight, 0));

	// On exclut tout le GROUPE de la cible, pas seulement sa part : sinon la sonde s'arrête
	// aussitôt sur le socle du bouton ou sur le mobilier de la boutique (mesuré : 0 stud de
	// chute sous ButtonPart) et le ruban n'atteint jamais le sol. Le personnage et le ruban
	// lui-même sont exclus pour la même raison.
	const excluded: Instance[] = [targetGroup(part)];
	const character = Players.LocalPlayer.Character;
	if (character) excluded.push(character);
	if (trail) excluded.push(trail.part);
	groundParams.FilterDescendantsInstances = excluded;
	const hit = Workspace.Raycast(base, new Vector3(0, -TARGET_GROUND_PROBE, 0), groundParams);
	// Sans sol trouvé (cible au-dessus du vide), on se rabat sur son pied.
	return hit ? hit.Position.add(new Vector3(0, TARGET_GROUND_LIFT, 0)) : base;
}

export const TutorialArrow = {
	// Ruban au sol vers `part` + chevron si la cible est hors champ.
	pointAtWorld(part: BasePart): void {
		TutorialArrow.clear();

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			// Le chevron vit dans le ScreenGui du tutorial, qui peut être détruit puis
			// reconstruit pendant que cette boucle tourne : il doit être résolu ICI, à chaque
			// frame, jamais capturé hors boucle — sinon on écrit dans une instance orpheline
			// pendant que le vrai chevron reste invisible.
			const chev = ensureChevron();
			const ribbon = ensureTrail();
			const root = characterRoot();
			const target = targetAimPoint(part);
			// La caméra doit être lue à chaque frame car elle est nil au spawn.
			const camera = Workspace.CurrentCamera;
			if (!root || !camera) {
				ribbon.surface.Enabled = false;
				chev.Visible = false;
				return;
			}

			// Départ au TORSE du joueur (le HumanoidRootPart), arrivée au SOL sous la cible : le
			// ruban est tendu en 3D, pas rabattu à l'horizontale. C'est ce qui fait qu'il plonge
			// vers la cible quand le joueur saute, au lieu de monter avec lui en restant plat.
			const start = root.Position.add(new Vector3(0, TRAIL_START_OFFSET, 0));
			const span = target.sub(start);
			const length = span.Magnitude;
			if (length < TRAIL_MIN_LENGTH) {
				// Arrivé : plus rien à montrer, et à cette distance le ruban serait plus large
				// que long.
				ribbon.surface.Enabled = false;
			} else {
				ribbon.surface.Enabled = true;
				const direction = span.Unit;
				const mid = start.add(span.mul(0.5));
				// Seules la LONGUEUR (Y local) et la position changent : largeur et épaisseur
				// sont constantes, et PixelsPerStud étant fixe, allonger le ruban AJOUTE des
				// chevrons au lieu de les étirer.
				ribbon.part.Size = new Vector3(TRAIL_WIDTH, length, TRAIL_THICKNESS);
				// Le +Y local — le haut du GUI — vise la cible. La largeur (X local) reste
				// HORIZONTALE : la plaque bascule donc comme une rampe, mais ne roule jamais
				// sur elle-même. Cible à la verticale = projection au sol nulle : largeur
				// arbitraire, l'orientation n'a alors plus de sens de toute façon.
				const flat = new Vector3(direction.X, 0, direction.Z);
				const side = flat.Magnitude > 0.001 ? new Vector3(flat.Z, 0, -flat.X).Unit : new Vector3(1, 0, 0);
				// vZ = X × Y : la face avant (-Z), celle qui porte le GUI, regarde vers le haut,
				// inclinée du même angle que le ruban.
				ribbon.part.CFrame = CFrame.fromMatrix(mid, side, direction, side.Cross(direction));

				// Défilement : l'image fait une tuile de plus que le ruban et remonte d'une tuile
				// par cycle, donc les chevrons avancent vers la cible sans trou ni saut.
				const phase = (elapsed % SCROLL_PERIOD) / SCROLL_PERIOD;
				ribbon.image.Position = new UDim2(0, 0, 0, -math.floor(phase * TILE_PIXELS));
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
				// `clamped` est en coordonnées VIEWPORT (origine sous la barre Roblox) et le
				// chevron vit dans TutorialUI (origine en haut de l'écran) : même conversion
				// que pour la flèche GUI, sinon le chevron est trop haut de l'inset.
				const chevOrigin = TutorialUI.originOffset();
				chev.Position = new UDim2(0, clamped.X - chevOrigin.X, 0, clamped.Y - chevOrigin.Y);
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
			// La cible vit dans InGameUI, la flèche dans TutorialUI : deux ScreenGuis, deux
			// repères (voir TutorialUI.originOffset). Sans cette conversion — la même que dans
			// TutorialFocus.layoutDim — la flèche est décalée vers le haut de la hauteur de la
			// barre Roblox et ne vise plus le milieu de la cible. Lu à chaque frame, jamais
			// mis en cache : TutorialUI peut être reconstruit pendant que la boucle tourne.
			const origin = TutorialUI.originOffset();
			const pos = target.AbsolutePosition.sub(origin);
			const size = target.AbsoluteSize;
			const bob = math.sin(elapsed * 4) * GUI_BOB;
			// À gauche du bord gauche, centrée verticalement, pointant vers la droite (90°).
			arrow.Position = new UDim2(0, pos.X - GUI_ARROW_GAP - GUI_ARROW_SIZE / 2 + bob, 0, pos.Y + size.Y / 2);
			arrow.Rotation = 90;
		});
	},

	clear(): void {
		stopRender();
		elapsed = 0;
		if (trail) {
			trail.part.Destroy();
			trail = undefined;
		}
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
