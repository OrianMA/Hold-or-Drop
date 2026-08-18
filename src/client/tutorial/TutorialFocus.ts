import { RunService } from "@rbxts/services";
import { TutorialFocus as FocusMode } from "shared/tutorial/TutorialTypes";
import { TutorialUI, Z_DIM } from "./TutorialUI";

// Mise en avant d'une cible GUI.
//   "dim"       → 4 frames autour du rectangle de la cible : la cible reste visible,
//                 tout le reste est assombri. PUREMENT VISUEL (Active = false) : le
//                 dim MONTRE où regarder, il ne bloque plus rien — c'est TutorialGate
//                 (lockGui) qui est l'unique mécanisme de blocage de l'input. Ne pas
//                 repasser Active à true en pensant "restaurer" un blocage : il n'y en
//                 a jamais eu ici, et ça recouvrirait le bouton Skip (DisplayOrder 100
//                 de TutorialUI est au-dessus de InGameUI).
//   "highlight" → contour pulsé sur la cible, SANS assombrir — pour un step où la scène
//                 derrière doit rester visible. On ne touche JAMAIS à la taille de la
//                 cible : une interruption laisserait le GUI du jeu déformé.
// Le contour pulsé est posé dans les DEUX modes ; seul le dim est optionnel.

const DIM_COLOR = Color3.fromRGB(0, 0, 0);
const DIM_TRANSPARENCY = 0.55;
const STROKE_NAME = "TutorialHighlightStroke";
const STROKE_COLOR = Color3.fromRGB(255, 226, 92);
const STROKE_MIN = 2;
const STROKE_MAX = 6;
const PULSE_SPEED = 5;
// Marge, en pixels, entre le rectangle de la cible et le trou laissé dans le dim. Sans
// elle les bandes sombres viennent mordre le contour pulsé, qui est dessiné EN DEHORS de
// la cible (ApplyStrokeMode.Border) et atteint STROKE_MAX d'épaisseur au pic de la pulse.
// En pixels et non en scale : le contour lui-même est en pixels, la marge doit le suivre.
const HOLE_PADDING = STROKE_MAX + 6;

let dimFrames: Frame[] = [];
let stroke: UIStroke | undefined;
let renderConn: RBXScriptConnection | undefined;
let elapsed = 0;

function makeDimFrame(parent: Instance): Frame {
	const frame = new Instance("Frame");
	frame.Name = "TutorialDim";
	frame.BackgroundColor3 = DIM_COLOR;
	frame.BackgroundTransparency = DIM_TRANSPARENCY;
	frame.BorderSizePixel = 0;
	frame.ZIndex = Z_DIM; // sous le bandeau et les flèches, qui doivent rester lisibles
	frame.Active = false; // purement visuel — TutorialGate.lockGui bloque l'input
	frame.Parent = parent;
	return frame;
}

// Place les 4 bandes autour du rectangle de la cible, élargi de HOLE_PADDING pour que le
// contour pulsé tienne dans le trou.
function layoutDim(target: GuiObject): void {
	if (dimFrames.size() < 4) return;
	// La cible vit dans InGameUI, les bandes dans TutorialUI : deux ScreenGuis, deux
	// repères de coordonnées différents (voir TutorialUI.originOffset). On lit l'offset
	// à CHAQUE appel plutôt que de le mettre en cache — l'appel se fait déjà à chaque
	// frame (voir RenderStepped ci-dessous), donc toute reconstruction de TutorialUI
	// (cadre de référence recréé) est automatiquement suivie.
	const origin = TutorialUI.originOffset();
	const pos = target.AbsolutePosition.sub(origin);
	const size = target.AbsoluteSize;

	// Bords du trou. La marge n'agrandit QUE le trou : la cible elle-même n'est jamais
	// touchée (une interruption laisserait le GUI du jeu déformé).
	const left = pos.X - HOLE_PADDING;
	const top = pos.Y - HOLE_PADDING;
	const right = pos.X + size.X + HOLE_PADDING;
	const bottom = pos.Y + size.Y + HOLE_PADDING;
	const holeHeight = bottom - top;

	// haut
	dimFrames[0].Position = new UDim2(0, 0, 0, 0);
	dimFrames[0].Size = new UDim2(1, 0, 0, math.max(top, 0));
	// bas
	dimFrames[1].Position = new UDim2(0, 0, 0, bottom);
	dimFrames[1].Size = new UDim2(1, 0, 1, -bottom);
	// gauche
	dimFrames[2].Position = new UDim2(0, 0, 0, top);
	dimFrames[2].Size = new UDim2(0, math.max(left, 0), 0, holeHeight);
	// droite
	dimFrames[3].Position = new UDim2(0, right, 0, top);
	dimFrames[3].Size = new UDim2(1, -right, 0, holeHeight);
}

export const TutorialFocus = {
	apply(target: GuiObject, mode: FocusMode): void {
		TutorialFocus.clear();
		const gui = TutorialUI.ensure();

		if (mode === "dim") {
			for (let i = 0; i < 4; i++) dimFrames.push(makeDimFrame(gui));
			layoutDim(target);
		}

		const outline = new Instance("UIStroke");
		outline.Name = STROKE_NAME;
		outline.Color = STROKE_COLOR;
		outline.Thickness = STROKE_MIN;
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		outline.Parent = target;
		stroke = outline;

		renderConn = RunService.RenderStepped.Connect((dt) => {
			elapsed += dt;
			if (stroke) {
				const t = (math.sin(elapsed * PULSE_SPEED) + 1) / 2;
				stroke.Thickness = STROKE_MIN + (STROKE_MAX - STROKE_MIN) * t;
			}
			// La cible peut bouger/se redimensionner (layouts, tweens) → on suit.
			if (dimFrames.size() > 0) layoutDim(target);
		});
	},

	clear(): void {
		if (renderConn) {
			renderConn.Disconnect();
			renderConn = undefined;
		}
		elapsed = 0;
		for (const frame of dimFrames) frame.Destroy();
		dimFrames = [];
		if (stroke) {
			stroke.Destroy();
			stroke = undefined;
		}
	},
};
