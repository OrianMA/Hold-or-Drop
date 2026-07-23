import { Players, TweenService } from "@rbxts/services";
import { Events } from "shared/Event";

// Generic "flash text in the HUD" controller.
// Animates InGameUI/InformationTextCanvasGroup with the same timings as the old
// ButtonFinishGame/FinishTextCanvasGroup (which it replaces). The contained
// TextLabel's Text and TextColor3 are overwritten on each show() call.
//
//   InformationText.show("Finish");                           // white, default
//   InformationText.show("Not enough money", new Color3(1, 0, 0));  // red
//
// Calling show() while a previous flash is mid-animation cancels it cleanly
// and restarts from full transparency so the new message isn't lost.

const FADE_IN_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const FADE_OUT_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const DEFAULT_HOLD = 0.2;

const DEFAULT_COLOR = new Color3(1, 1, 1);
const CANVAS_NAME = "InformationTextCanvasGroup";
const LABEL_NAME = "InformationText";

let cachedCanvas: CanvasGroup | undefined;
let activeTweens: Tween[] = [];
let activeDelayToken = 0;

function findCanvas(): CanvasGroup | undefined {
	if (cachedCanvas && cachedCanvas.Parent !== undefined) return cachedCanvas;
	const gui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	if (!gui) return undefined;
	for (const desc of gui.GetDescendants()) {
		if (desc.Name === CANVAS_NAME && desc.IsA("CanvasGroup")) {
			cachedCanvas = desc;
			return desc;
		}
	}
	return undefined;
}

// Specifically named TextLabel ("InformationText") — recursive search covers
// the canonical InformationTextCanvasGroup → FrameParent → InformationText
// path as well as any future re-layout.
function findLabel(canvas: CanvasGroup): TextLabel | undefined {
	const found = canvas.FindFirstChild(LABEL_NAME, true);
	return found?.IsA("TextLabel") ? found : undefined;
}

function cancelActive(): void {
	for (const t of activeTweens) t.Cancel();
	activeTweens = [];
	activeDelayToken += 1; // invalidates any pending task.delay fade-out
}

export const InformationText = {
	// Exposed for callers that need to sequence other animations around the
	// flash (e.g. EndGameAnimation waits FADE_IN_TIME + HOLD_TIME before
	// starting the multiplier drain).
	FADE_IN_TIME: FADE_IN_TI.Time,
	HOLD_TIME: DEFAULT_HOLD,
	FADE_OUT_TIME: FADE_OUT_TI.Time,

	// Clears a flash instantly, mid-animation. Used when the end-game payout is
	// flushed by another popup — the "Finish" text must not linger over the new screen.
	hide(): void {
		const canvas = findCanvas();
		if (!canvas) return;
		cancelActive();
		canvas.GroupTransparency = 1;
	},

	// holdSeconds: how long the text stays fully opaque between fade-in and
	// fade-out. Falls back to DEFAULT_HOLD (0.2 s — matches the original
	// ButtonFinishGame timing) when omitted.
	show(text: string, color?: Color3, holdSeconds?: number): void {
		const canvas = findCanvas();
		if (!canvas) {
			warn(`InformationText: ${CANVAS_NAME} not found under PlayerGui`);
			return;
		}
		const label = findLabel(canvas);
		if (label) {
			label.Text = text;
			label.TextColor3 = color ?? DEFAULT_COLOR;
		}

		cancelActive();
		const myToken = activeDelayToken;

		canvas.GroupTransparency = 1;
		canvas.Visible = true;

		const fadeIn = TweenService.Create(canvas, FADE_IN_TI, { GroupTransparency: 0 });
		activeTweens.push(fadeIn);
		fadeIn.Play();

		const hold = holdSeconds ?? DEFAULT_HOLD;
		task.delay(FADE_IN_TI.Time + hold, () => {
			// A newer show() invalidated this fade-out — bail.
			if (myToken !== activeDelayToken) return;
			const fadeOut = TweenService.Create(canvas, FADE_OUT_TI, { GroupTransparency: 1 });
			activeTweens.push(fadeOut);
			fadeOut.Play();
		});
	},
};

export function init(): void {
	Events.InformationTextEvent.OnClientEvent.Connect((text: string, color?: Color3, holdSeconds?: number) => {
		InformationText.show(text, color, holdSeconds);
	});
}
