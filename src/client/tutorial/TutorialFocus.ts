import { RunService } from "@rbxts/services";
import { TutorialFocus as FocusMode } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Mise en avant d'une cible GUI.
//   "dim"       → 4 frames autour du rectangle de la cible : la cible reste CLIQUABLE
//                 (rien par-dessus), tout le reste est couvert par des frames qui
//                 absorbent l'input (Active = true).
//   "highlight" → contour pulsé sur la cible, SANS assombrir (steps en vol : la fusée
//                 doit rester visible). On ne touche JAMAIS à la taille de la cible :
//                 une interruption laisserait le GUI du jeu déformé.

const DIM_COLOR = Color3.fromRGB(0, 0, 0);
const DIM_TRANSPARENCY = 0.55;
const STROKE_NAME = "TutorialHighlightStroke";
const STROKE_COLOR = Color3.fromRGB(255, 226, 92);
const STROKE_MIN = 2;
const STROKE_MAX = 6;
const PULSE_SPEED = 5;

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
	frame.Active = true; // absorbe les clics
	frame.Parent = parent;
	return frame;
}

// Place les 4 bandes autour du rectangle (x, y, w, h) de la cible.
function layoutDim(target: GuiObject): void {
	if (dimFrames.size() < 4) return;
	const pos = target.AbsolutePosition;
	const size = target.AbsoluteSize;

	// haut
	dimFrames[0].Position = new UDim2(0, 0, 0, 0);
	dimFrames[0].Size = new UDim2(1, 0, 0, math.max(pos.Y, 0));
	// bas
	dimFrames[1].Position = new UDim2(0, 0, 0, pos.Y + size.Y);
	dimFrames[1].Size = new UDim2(1, 0, 1, -(pos.Y + size.Y));
	// gauche
	dimFrames[2].Position = new UDim2(0, 0, 0, pos.Y);
	dimFrames[2].Size = new UDim2(0, math.max(pos.X, 0), 0, size.Y);
	// droite
	dimFrames[3].Position = new UDim2(0, pos.X + size.X, 0, pos.Y);
	dimFrames[3].Size = new UDim2(1, -(pos.X + size.X), 0, size.Y);
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
