import { ReplicatedStorage, TweenService } from "@rbxts/services";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { MainUIController } from "client/ui/MainUIController";
import { FormatCash } from "shared/NumberFormat";

// ── Tuning ────────────────────────────────────────────────────────────────────

const FINISH_FADE_IN_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const FINISH_FADE_OUT_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FINISH_HOLD = 2;

const FLOAT_INTERVAL = 0.3;
const CHUNK_TARGET_RATIO = 5; // each floating value targets multiplier / 5
const MAX_CHUNK = 15;

const MULTIPLIER_TWEEN_TI = new TweenInfo(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const BASE_CASH_TWEEN_TI = new TweenInfo(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const FRAME_FADE_OUT_TI = new TweenInfo(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// BaseCash growth — same red-tinge style as the in-game multiplier label
const BASE_CASH_MAX_SIZE_INCREASE = 40;
const BASE_CASH_TARGET_COLOR = new Color3(1, 0.25, 0.25);

const FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate";
const FLOATING_FLY_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FLOATING_BUMP_IN_TI = new TweenInfo(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const FLOATING_BUMP_OUT_TI = new TweenInfo(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// ── Chunk split ───────────────────────────────────────────────────────────────

// Splits `multiplier` into floating-text values that:
//  • each target multiplier / CHUNK_TARGET_RATIO (capped at MAX_CHUNK)
//  • use a max of one decimal place (so minimum chunk = 0.1)
//  • sum exactly to `multiplier`
// Works in tenths to avoid float drift, then distributes the remainder one tenth
// at a time across the first chunks.
export function splitMultiplier(multiplier: number): number[] {
	const totalUnits = math.round(multiplier * 10);
	if (totalUnits <= 0) return [];

	const targetChunkUnits = math.max(1, math.min(MAX_CHUNK * 10, math.round(totalUnits / CHUNK_TARGET_RATIO)));
	const count = math.max(1, math.round(totalUnits / targetChunkUnits));

	const baseUnits = math.floor(totalUnits / count);
	const remainder = totalUnits - baseUnits * count;

	const chunks: number[] = [];
	for (let i = 0; i < count; i++) {
		const units = baseUnits + (i < remainder ? 1 : 0);
		chunks.push(units / 10);
	}
	return chunks;
}

// ── Formatting ────────────────────────────────────────────────────────────────

function formatMultiplier(value: number): string {
	return `${tostring(math.round(value * 10) / 10)}x`;
}

function formatCash(value: number): string {
	return FormatCash(value);
}

// ── Floating chunk ────────────────────────────────────────────────────────────

interface FloatingHandlers {
	onSpawn: (chunk: number) => void;
	onArrived: (chunk: number) => void;
}

let cachedTemplate: Frame | undefined;
function getFloatingTemplate(): Frame | undefined {
	if (cachedTemplate) return cachedTemplate;
	const found = ReplicatedStorage.FindFirstChild(FLOATING_TEMPLATE_NAME);
	if (found?.IsA("Frame")) cachedTemplate = found;
	return cachedTemplate;
}

function spawnFloatingChunk(
	parent: ScreenGui,
	chunk: number,
	originLabel: TextLabel,
	targetLabel: TextLabel,
	handlers: FloatingHandlers,
): void {
	const template = getFloatingTemplate();
	if (!template) {
		// Template missing — still fire callbacks so the pipeline stays coherent
		handlers.onSpawn(chunk);
		task.delay(FLOATING_FLY_TI.Time, () => handlers.onArrived(chunk));
		return;
	}

	const screenSize = parent.AbsoluteSize;
	if (screenSize.X === 0) {
		handlers.onSpawn(chunk);
		handlers.onArrived(chunk);
		return;
	}

	const frame = template.Clone();
	frame.Name = "EndGameFloatingChunk";
	frame.AnchorPoint = new Vector2(0.5, 0.5);
	frame.ZIndex = 30;
	frame.Visible = true;
	frame.Parent = parent;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${tostring(math.round(chunk * 10) / 10)}`;

	const icon = frame.FindFirstChild("Icon") as ImageLabel | undefined;
	const uiScale = new Instance("UIScale");
	uiScale.Scale = 0.9;
	uiScale.Parent = icon ?? frame;

	// Spawn next to the MultiplierText
	const originCenter = originLabel.AbsolutePosition.add(originLabel.AbsoluteSize.div(2));
	const offsetX = originLabel.AbsoluteSize.X * 0.6 + math.random(-20, 20);
	const offsetY = math.random(-10, 10);
	frame.Position = new UDim2(
		(originCenter.X + offsetX) / screenSize.X,
		0,
		(originCenter.Y + offsetY) / screenSize.Y,
		0,
	);

	// Immediate drain — happens on spawn, per spec
	handlers.onSpawn(chunk);

	TweenService.Create(uiScale, FLOATING_BUMP_IN_TI, { Scale: 1.1 }).Play();
	task.delay(FLOATING_BUMP_IN_TI.Time, () => {
		TweenService.Create(uiScale, FLOATING_BUMP_OUT_TI, { Scale: 1.0 }).Play();

		task.delay(FLOATING_BUMP_OUT_TI.Time + 0.04, () => {
			const targetCenter = targetLabel.AbsolutePosition.add(targetLabel.AbsoluteSize.div(2));
			const targetPos = new UDim2(targetCenter.X / screenSize.X, 0, targetCenter.Y / screenSize.Y, 0);
			const fly = TweenService.Create(frame, FLOATING_FLY_TI, { Position: targetPos });
			fly.Completed.Connect(() => {
				frame.Destroy();
				handlers.onArrived(chunk);
			});
			fly.Play();
		});
	});
}

// ── Multiplier & BaseCash visuals ─────────────────────────────────────────────

interface MultiplierStyleEndpoints {
	startSize: number;
	startColor: Color3;
	endSize: number;
	endColor: Color3;
}

function applyMultiplierStyle(
	label: TextLabel,
	value: number,
	startValue: number,
	endpoints: MultiplierStyleEndpoints,
): void {
	const factor = startValue > 0 ? math.clamp(value / startValue, 0, 1) : 0;
	const size = endpoints.endSize + (endpoints.startSize - endpoints.endSize) * factor;
	const color = endpoints.endColor.Lerp(endpoints.startColor, factor);
	label.Text = formatMultiplier(value);
	TweenService.Create(label, MULTIPLIER_TWEEN_TI, { TextSize: size, TextColor3: color }).Play();
}

interface BaseCashStyleEndpoints {
	baseSize: number;
	baseColor: Color3;
	totalGrowthCash: number; // cash needed to reach full red tint
}

function applyBaseCashStyle(label: TextLabel, currentCash: number, baseCash: number, endpoints: BaseCashStyleEndpoints): void {
	const progress =
		endpoints.totalGrowthCash > 0 ? math.clamp((currentCash - baseCash) / endpoints.totalGrowthCash, 0, 1) : 0;
	const size = endpoints.baseSize + progress * BASE_CASH_MAX_SIZE_INCREASE;
	const color = endpoints.baseColor.Lerp(BASE_CASH_TARGET_COLOR, progress);
	label.Text = formatCash(currentCash);
	TweenService.Create(label, BASE_CASH_TWEEN_TI, { TextSize: size, TextColor3: color }).Play();
}

// ── Public orchestrator ───────────────────────────────────────────────────────

interface EndGameRefs {
	frame: Frame;
	finishCanvas: CanvasGroup;
	multiplierText: TextLabel;
	baseCashText: TextLabel;
	screenGui: ScreenGui;
}

function resolveRefs(frame: Frame): EndGameRefs | undefined {
	const finishCanvas = frame.WaitForChild("FinishTextCanvasGroup", 5);
	const multiplierText = frame.WaitForChild("MultiplierText", 5);
	const baseCashText = frame.WaitForChild("BaseCashText", 5);
	const screenGui = frame.FindFirstAncestorOfClass("ScreenGui");
	if (
		!finishCanvas?.IsA("CanvasGroup") ||
		!multiplierText?.IsA("TextLabel") ||
		!baseCashText?.IsA("TextLabel") ||
		!screenGui
	) {
		warn("EndGameAnimation: missing one of FinishTextCanvasGroup/MultiplierText/BaseCashText");
		return undefined;
	}
	return {
		frame,
		finishCanvas: finishCanvas as CanvasGroup,
		multiplierText: multiplierText as TextLabel,
		baseCashText: baseCashText as TextLabel,
		screenGui: screenGui as ScreenGui,
	};
}

// Runs the full ButtonFinishGame animation, then calls onComplete().
// Safe to call from a regular task (uses task.wait internally).
export function runEndGameAnimation(frame: Frame, baseCash: number, multiplier: number, onComplete: () => void): void {
	const refs = resolveRefs(frame);
	if (!refs) {
		onComplete();
		return;
	}
	const { finishCanvas, multiplierText, baseCashText, screenGui } = refs;

	// ── Multiplier text — match the in-game label's last appearance ───────────
	const snapshot = MultiplierVisuals.getLast();
	const inGameSize = snapshot?.size ?? multiplierText.TextSize;
	const inGameColor = snapshot?.color ?? multiplierText.TextColor3;
	// "Resting" state we tween back to as the multiplier drains to 0
	const restingSize = multiplierText.TextSize;
	const restingColor = multiplierText.TextColor3;

	multiplierText.TextSize = inGameSize;
	multiplierText.TextColor3 = inGameColor;
	multiplierText.Text = formatMultiplier(multiplier);

	// ── BaseCash text — start at the button's baseCash ────────────────────────
	const baseCashBaseSize = baseCashText.TextSize;
	const baseCashBaseColor = baseCashText.TextColor3;
	baseCashText.Text = formatCash(baseCash);
	baseCashText.TextSize = baseCashBaseSize;
	baseCashText.TextColor3 = baseCashBaseColor;
	// Reset transparency in case the previous run left it hidden by the fly tween
	baseCashText.TextTransparency = 0;
	baseCashText.TextStrokeTransparency = 0;
	baseCashText.Visible = true;

	// ── Finish text fade in → hold 2s → fade out ──────────────────────────────
	finishCanvas.GroupTransparency = 1;
	finishCanvas.Visible = true;
	TweenService.Create(finishCanvas, FINISH_FADE_IN_TI, { GroupTransparency: 0 }).Play();
	task.wait(FINISH_FADE_IN_TI.Time + FINISH_HOLD);
	TweenService.Create(finishCanvas, FINISH_FADE_OUT_TI, { GroupTransparency: 1 }).Play();

	// ── Drain multiplier into base cash via floating chunks ───────────────────
	const chunks = splitMultiplier(multiplier);

	if (chunks.size() === 0) {
		// Nothing to animate — close after the fade-out
		task.wait(FINISH_FADE_OUT_TI.Time);
		flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete);
		return;
	}

	const multiplierEndpoints: MultiplierStyleEndpoints = {
		startSize: inGameSize,
		startColor: inGameColor,
		endSize: restingSize,
		endColor: restingColor,
	};
	const baseCashEndpoints: BaseCashStyleEndpoints = {
		baseSize: baseCashBaseSize,
		baseColor: baseCashBaseColor,
		totalGrowthCash: baseCash * multiplier,
	};

	let remainingMultiplier = multiplier;
	let currentCash = baseCash;
	let arrivedCount = 0;

	for (let i = 0; i < chunks.size(); i++) {
		const chunk = chunks[i];
		spawnFloatingChunk(screenGui, chunk, multiplierText, baseCashText, {
			onSpawn: (c) => {
				// Spec: as soon as a floating text appears, MultiplierText drops by c
				remainingMultiplier = math.max(0, remainingMultiplier - c);
				applyMultiplierStyle(multiplierText, remainingMultiplier, multiplier, multiplierEndpoints);
			},
			onArrived: (c) => {
				// Spec: on tween end, BaseCashText grows by c × baseCash
				currentCash += baseCash * c;
				applyBaseCashStyle(baseCashText, currentCash, baseCash, baseCashEndpoints);
				arrivedCount += 1;
				if (arrivedCount >= chunks.size()) {
					task.delay(0.4, () => flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete));
				}
			},
		});
		task.wait(FLOAT_INTERVAL);
	}
}

// Tween settings for the final "deposit" of the cash into the persistent HUD
const FLY_TO_MONEY_TI = new TweenInfo(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FLY_TO_MONEY_FADE_TI = new TweenInfo(0.55, Enum.EasingStyle.Linear, Enum.EasingDirection.Out);
const FLY_TO_MONEY_SHRINK = 0.4;

// Clones BaseCashText, parents it to the ScreenGui so it can move freely across
// the screen, hides the original (still inside the popup frame so it's reusable
// for the next game), then tweens the clone to MoneyParent (inside MainUI) while
// fading. Falls back to a simple fade if MoneyParent isn't found.
function flyBaseCashAndComplete(
	frame: Frame,
	baseCashText: TextLabel,
	screenGui: ScreenGui,
	onComplete: () => void,
): void {
	const moneyParent = MainUIController.getMoneyParent();
	const screenSize = screenGui.AbsoluteSize;
	const cashAbsSize = baseCashText.AbsoluteSize;
	const cashAbsCenter = baseCashText.AbsolutePosition.add(cashAbsSize.div(2));

	const finishFrame = () => {
		baseCashText.TextTransparency = 0;
		baseCashText.TextStrokeTransparency = 0;
		baseCashText.Visible = true;
		onComplete();
	};

	if (!moneyParent || screenSize.X === 0 || cashAbsSize.X === 0) {
		// No target / no layout — just fade and finish
		const tween = TweenService.Create(baseCashText, FLY_TO_MONEY_FADE_TI, {
			TextTransparency: 1,
			TextStrokeTransparency: 1,
		});
		tween.Completed.Connect(() => finishFrame());
		tween.Play();
		return;
	}

	const flyLabel = baseCashText.Clone();
	flyLabel.Name = "BaseCashFlyClone";
	flyLabel.AnchorPoint = new Vector2(0.5, 0.5);
	flyLabel.Position = new UDim2(0, cashAbsCenter.X, 0, cashAbsCenter.Y);
	flyLabel.Size = new UDim2(0, cashAbsSize.X, 0, cashAbsSize.Y);
	flyLabel.ZIndex = 50;
	flyLabel.Parent = screenGui;

	// Hide the original so the popup looks empty while the clone flies — the
	// next run resets these properties at the top of runEndGameAnimation.
	baseCashText.TextTransparency = 1;
	baseCashText.TextStrokeTransparency = 1;

	const moneyCenter = moneyParent.AbsolutePosition.add(moneyParent.AbsoluteSize.div(2));
	const targetPos = new UDim2(0, moneyCenter.X, 0, moneyCenter.Y);
	const targetSize = new UDim2(0, cashAbsSize.X * FLY_TO_MONEY_SHRINK, 0, cashAbsSize.Y * FLY_TO_MONEY_SHRINK);

	TweenService.Create(flyLabel, FLY_TO_MONEY_TI, { Position: targetPos, Size: targetSize }).Play();
	const fadeTween = TweenService.Create(flyLabel, FLY_TO_MONEY_FADE_TI, {
		TextTransparency: 1,
		TextStrokeTransparency: 1,
	});
	fadeTween.Completed.Connect(() => {
		flyLabel.Destroy();
		finishFrame();
	});
	fadeTween.Play();
}
