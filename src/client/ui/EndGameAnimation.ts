import { ReplicatedStorage, TweenService } from "@rbxts/services";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { MainUIController } from "client/ui/MainUIController";
import { InformationText } from "client/ui/InformationText";
import { FormatCash } from "shared/NumberFormat";

// ── Tuning ────────────────────────────────────────────────────────────────────

const FINISH_TEXT = "Finish";

const FLOAT_INTERVAL = 0.3;
const CHUNK_TARGET_RATIO = 5; // each floating value targets multiplier / 5
const MAX_CHUNK = 15;

const MULTIPLIER_TWEEN_TI = new TweenInfo(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const BASE_CASH_TWEEN_TI = new TweenInfo(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const FRAME_FADE_OUT_TI = new TweenInfo(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// Penalty animation when the player died (lossMultiplier < 1). Same TweenInfo
// as the MainUI MoneyText counter so the two animations feel cohesive.
const LOSS_PENALTY_TI = new TweenInfo(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// BaseCash growth — same red-tinge style as the in-game multiplier label
const BASE_CASH_MAX_SIZE_INCREASE = 40;
const BASE_CASH_TARGET_COLOR = new Color3(1, 0.25, 0.25);

const FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate";
const FLOATING_FLY_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FLOATING_BUMP_IN_TI = new TweenInfo(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const FLOATING_BUMP_OUT_TI = new TweenInfo(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// New "explode-out then fly" sequence: the chunk spawns on the MultiplierText,
// disperses in a random direction, briefly holds, then flies to BaseCashText.
const FLOATING_DISPERSE_TI = new TweenInfo(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out);
const FLOATING_DISPERSE_MIN = 70; // px
const FLOATING_DISPERSE_MAX = 130; // px
const FLOATING_HOLD = 0.12; // pause between dispersion and fly-to-cash

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
		task.delay(FLOATING_DISPERSE_TI.Time + FLOATING_HOLD + FLOATING_FLY_TI.Time, () =>
			handlers.onArrived(chunk),
		);
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

	// ── 1. Spawn exactly ON MultiplierText center ─────────────────────────────
	const originCenter = originLabel.AbsolutePosition.add(originLabel.AbsoluteSize.div(2));
	frame.Position = new UDim2(0, originCenter.X, 0, originCenter.Y);

	// Immediate drain — happens on spawn, per spec
	handlers.onSpawn(chunk);

	// Quick bump for that satisfying "pop" feel
	TweenService.Create(uiScale, FLOATING_BUMP_IN_TI, { Scale: 1.1 }).Play();
	task.delay(FLOATING_BUMP_IN_TI.Time, () => {
		TweenService.Create(uiScale, FLOATING_BUMP_OUT_TI, { Scale: 1.0 }).Play();
	});

	// ── 2. Disperse in a random direction (the "explode-out") ────────────────
	const angle = math.random() * math.pi * 2;
	const distance = math.random(FLOATING_DISPERSE_MIN, FLOATING_DISPERSE_MAX);
	const dispersePos = new UDim2(
		0,
		originCenter.X + math.cos(angle) * distance,
		0,
		originCenter.Y + math.sin(angle) * distance,
	);
	const disperse = TweenService.Create(frame, FLOATING_DISPERSE_TI, { Position: dispersePos });
	disperse.Play();

	disperse.Completed.Connect(() => {
		// ── 3. Brief hold so the eye registers where it landed ───────────────
		task.delay(FLOATING_HOLD, () => {
			// Target re-read at fly-time — handles UI layout shifts mid-animation.
			const targetCenter = targetLabel.AbsolutePosition.add(targetLabel.AbsoluteSize.div(2));
			const targetPos = new UDim2(0, targetCenter.X, 0, targetCenter.Y);

			// ── 4. Fly to BaseCashText ───────────────────────────────────────
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
	// Hide the whole label (text + any UIStroke children) the instant we hit 0
	// — TextSize alone leaves strokes painted, and TextTransparency doesn't
	// affect stroke transparency. Visible=false is the only clean kill switch.
	if (value <= 0) {
		label.Visible = false;
		return;
	}
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

function applyBaseCashStyle(
	label: TextLabel,
	currentCash: number,
	baseCash: number,
	endpoints: BaseCashStyleEndpoints,
): void {
	const progress =
		endpoints.totalGrowthCash > 0 ? math.clamp((currentCash - baseCash) / endpoints.totalGrowthCash, 0, 1) : 0;
	const size = endpoints.baseSize + progress * BASE_CASH_MAX_SIZE_INCREASE;
	const color = endpoints.baseColor.Lerp(BASE_CASH_TARGET_COLOR, progress);
	label.Text = formatCash(currentCash);
	TweenService.Create(label, BASE_CASH_TWEEN_TI, { TextSize: size, TextColor3: color }).Play();
}

// ── Public orchestrator ───────────────────────────────────────────────────────

// Captured on the FIRST runEndGameAnimation call so every subsequent run can
// reset the label back to its Studio-authored state. Without this snapshot,
// each run would read `baseCashText.TextSize` *after* the previous run grew it,
// so a second game would start oversized and grow again — compounding the size
// across runs.
let initialBaseCashSize: number | undefined;
let initialBaseCashColor: Color3 | undefined;

interface EndGameRefs {
	frame: Frame;
	multiplierText: TextLabel;
	baseCashText: TextLabel;
	screenGui: ScreenGui;
}

function resolveRefs(frame: Frame): EndGameRefs | undefined {
	const multiplierText = frame.WaitForChild("MultiplierText", 5);
	const baseCashText = frame.WaitForChild("BaseCashText", 5);
	const screenGui = frame.FindFirstAncestorOfClass("ScreenGui");
	if (!multiplierText?.IsA("TextLabel") || !baseCashText?.IsA("TextLabel") || !screenGui) {
		warn("EndGameAnimation: missing one of MultiplierText/BaseCashText");
		return undefined;
	}
	return {
		frame,
		multiplierText: multiplierText as TextLabel,
		baseCashText: baseCashText as TextLabel,
		screenGui: screenGui as ScreenGui,
	};
}

// Tweens BaseCashText value + size from (startValue, startSize) down to
// (endValue, endSize) in parallel using LOSS_PENALTY_TI. Blocks the calling
// task until both tweens complete, then snaps to the exact final values to
// avoid float-precision drift. Uses a NumberValue proxy so the label re-formats
// every frame — the player sees the number count down rather than jump-cut.
function animateLossPenalty(
	label: TextLabel,
	startValue: number,
	endValue: number,
	startSize: number,
	endSize: number,
): void {
	const proxy = new Instance("NumberValue");
	proxy.Value = startValue;
	const conn = proxy.Changed.Connect((v) => {
		label.Text = formatCash(v);
	});

	TweenService.Create(proxy, LOSS_PENALTY_TI, { Value: endValue }).Play();
	const sizeTween = TweenService.Create(label, LOSS_PENALTY_TI, { TextSize: endSize });
	sizeTween.Play();
	sizeTween.Completed.Wait();

	conn.Disconnect();
	proxy.Destroy();
	label.Text = formatCash(endValue);
	label.TextSize = endSize;
}

// Runs the full ButtonFinishGame animation, then calls onComplete().
// Safe to call from a regular task (uses task.wait internally).
// lossMultiplier: 1 for wins (no penalty), < 1 for kills — applied to baseCash
// + text size via animateLossPenalty before the multiplier drain.
export function runEndGameAnimation(
	frame: Frame,
	baseCash: number,
	multiplier: number,
	lossMultiplier: number,
	onComplete: () => void,
): void {
	const refs = resolveRefs(frame);
	if (!refs) {
		onComplete();
		return;
	}
	const { multiplierText, baseCashText, screenGui } = refs;

	// ── Multiplier text — match the in-game label's last appearance ───────────
	const snapshot = MultiplierVisuals.getLast();
	const inGameSize = snapshot?.size ?? multiplierText.TextSize;
	const inGameColor = snapshot?.color ?? multiplierText.TextColor3;
	// Color we tween toward as the multiplier drains to 0 (size goes to 0 too
	// — see multiplierEndpoints — so the label fully shrinks and fades out).
	const restingColor = multiplierText.TextColor3;

	multiplierText.TextSize = inGameSize;
	multiplierText.TextColor3 = inGameColor;
	multiplierText.Text = formatMultiplier(multiplier);
	// Re-show in case the previous run hid the label when value hit 0
	multiplierText.Visible = true;

	// ── BaseCash text — start at the button's baseCash ────────────────────────
	// First-call snapshot — capture the true Studio-authored initial state so
	// every subsequent run starts from the same size/color instead of compounding
	// the previous run's growth.
	if (initialBaseCashSize === undefined) initialBaseCashSize = baseCashText.TextSize;
	if (initialBaseCashColor === undefined) initialBaseCashColor = baseCashText.TextColor3;
	const baseCashBaseSize = initialBaseCashSize;
	const baseCashBaseColor = initialBaseCashColor;
	// Reset the label to its initial state WHILE it's still hidden from the
	// previous run's fly clone — only after the reset do we flip Visible back
	// on, so the player never sees the grown size flash.
	baseCashText.Text = formatCash(baseCash);
	baseCashText.TextSize = baseCashBaseSize;
	baseCashText.TextColor3 = baseCashBaseColor;
	baseCashText.Visible = true;

	// ── "Finish" flash via the shared InformationText controller (in MainUI)
	// ─────────────────────────────────────────────────────────────────────────
	// Show fires-and-forgets the full fade-in/hold/fade-out cycle; we just need
	// to block until fade-in + hold are done before kicking off the penalty /
	// drain. The fade-out then runs in parallel with the rest of the animation.
	InformationText.show(FINISH_TEXT);
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME);

	// ── Loss penalty (killed mode only): shrink baseCash value + text size ───
	// Runs in parallel with the finish-canvas fade-out; we block here so the
	// drain phase below starts from the post-penalty value.
	let effectiveBaseCash = baseCash;
	let effectiveBaseSize = baseCashBaseSize;
	if (lossMultiplier < 1) {
		effectiveBaseCash = baseCash * lossMultiplier;
		effectiveBaseSize = baseCashBaseSize * lossMultiplier;
		animateLossPenalty(baseCashText, baseCash, effectiveBaseCash, baseCashBaseSize, effectiveBaseSize);
	}

	// ── Drain multiplier into base cash via floating chunks ───────────────────
	const chunks = splitMultiplier(multiplier);

	if (chunks.size() === 0) {
		// Nothing to animate — close after the "Finish" fade-out (penalty, if
		// any, has already waited longer than the fade-out so no extra wait).
		if (lossMultiplier >= 1) task.wait(InformationText.FADE_OUT_TIME);
		flyBaseCashAndComplete(frame, baseCashText, screenGui, onComplete);
		return;
	}

	const multiplierEndpoints: MultiplierStyleEndpoints = {
		startSize: inGameSize,
		startColor: inGameColor,
		endSize: 0, // value=0 → size=0 → fully vanished, paired with transparency=1
		endColor: restingColor,
	};

	// ── Drain math: keep the visual final equal to what the server actually
	//    credits (= effectiveBaseCash * multiplier).
	//
	//   • Win (lossMultiplier = 1): legacy behavior — start at effectiveBaseCash,
	//     each chunk c adds effectiveBaseCash * c → final = effectiveBaseCash
	//     * (1 + multiplier).
	//   • Kill (lossMultiplier < 1): start at effectiveBaseCash (post-penalty),
	//     grow toward effectiveBaseCash * multiplier — so total growth =
	//     effectiveBaseCash * (multiplier - 1), spread across chunks that sum to
	//     `multiplier`. Per-chunk addition = perUnitCash * c.
	//     Matches the killed-mode credit formula: baseCash * multiplier *
	//     LOOSE_WIN_MULTIPLIER = effectiveBaseCash * multiplier.
	const isLoss = lossMultiplier < 1;
	const perUnitCash = isLoss && multiplier > 0 ? (effectiveBaseCash * (multiplier - 1)) / multiplier : effectiveBaseCash;
	const totalGrowthCash = isLoss ? effectiveBaseCash * (multiplier - 1) : effectiveBaseCash * multiplier;

	const baseCashEndpoints: BaseCashStyleEndpoints = {
		baseSize: effectiveBaseSize,
		baseColor: baseCashBaseColor,
		totalGrowthCash,
	};

	let remainingMultiplier = multiplier;
	let currentCash = effectiveBaseCash;
	let arrivedCount = 0;

	const lastIndex = chunks.size() - 1;
	for (let i = 0; i < chunks.size(); i++) {
		const chunk = chunks[i];
		const isLastChunk = i === lastIndex;
		spawnFloatingChunk(screenGui, chunk, multiplierText, baseCashText, {
			onSpawn: (c) => {
				// Spec: as soon as a floating text appears, MultiplierText drops by c.
				// On the last chunk the residual may not hit exact 0 because of
				// float drift across chunk subtractions — so we hard-hide the
				// label here instead of relying on applyMultiplierStyle's
				// `value <= 0` check. Guarantees MultiplierText disappears the
				// instant the final "+X" pops out of it.
				if (isLastChunk) {
					remainingMultiplier = 0;
					multiplierText.Visible = false;
				} else {
					remainingMultiplier = math.max(0, remainingMultiplier - c);
					applyMultiplierStyle(multiplierText, remainingMultiplier, multiplier, multiplierEndpoints);
				}
			},
			onArrived: (c) => {
				// Spec: on tween end, BaseCashText grows by c × perUnitCash
				currentCash += perUnitCash * c;
				applyBaseCashStyle(baseCashText, currentCash, effectiveBaseCash, baseCashEndpoints);
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
// for the next game) via Visible=false so any UIStroke children disappear with
// it, then tweens the clone to MoneyParent (inside MainUI) while fading.
// Falls back to an instant hide if MoneyParent isn't found.
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
		// Reset to the captured initial size/color while still hidden so the
		// next run opens at the Studio-authored look. We deliberately do NOT
		// re-enable Visible here — the label must stay hidden until the popup
		// is reopened (runEndGameAnimation flips Visible back at its top).
		if (initialBaseCashSize !== undefined) baseCashText.TextSize = initialBaseCashSize;
		if (initialBaseCashColor !== undefined) baseCashText.TextColor3 = initialBaseCashColor;
		onComplete();
	};

	if (!moneyParent || screenSize.X === 0 || cashAbsSize.X === 0) {
		// No target / no layout — hide and finish (label stays hidden until
		// the next runEndGameAnimation reopens the frame).
		baseCashText.Visible = false;
		finishFrame();
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
	// next run flips Visible back at the top of runEndGameAnimation.
	baseCashText.Visible = false;

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
