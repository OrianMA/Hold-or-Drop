import { ReplicatedStorage, TweenService } from "@rbxts/services";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { InGameUIController } from "client/ui/InGameUIController";
import { MoneyDisplay } from "client/ui/MoneyDisplay";
import { InformationText } from "client/ui/InformationText";
import { FormatCash } from "shared/NumberFormat";

// ── ButtonFinishGame payout animation ───────────────────────────────────────────
//
// Sequence (after the "Finish" flash + optional kill penalty):
//   1.  MultiplierText flies into BaseCashText and disappears.
//   2.  BaseCashText counts up by the in-game multiplier (grow + red).
//       EffectiveBaseCash already folds in every money multiplier, so no separate
//       rebirth phase is needed.
//   3.  BaseCashText stays put (showing the full total) and sprays N floating texts
//       toward the money HUD; each arrival banks one chunk of the total.
//   4.  After the chunks land, a short pause, then the whole BaseCashText label flies
//       to the HUD cash as the final move.

// ── Tuning ──────────────────────────────────────────────────────────────────────

const FINISH_TEXT = "Finish";

// Phase 1 — MultiplierText merging into BaseCashText.
const MULTIPLIER_MERGE_TI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// Phase 2 — BaseCashText counting up to the total earned.
const BASE_CASH_COUNTUP_TI = new TweenInfo(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// Phase 3 — how many floating texts BaseCashText sprays, and how fast.
// Both tweakable: COUNT splits the total earned into COUNT chunks of
// totalEarn / COUNT; INTERVAL is the delay between each spawn.
const FLOATING_TEXT_COUNT = 8;
const FLOATING_TEXT_INTERVAL = 0.12; // seconds between each floating text

// Penalty animation when the player died (lossMultiplier < 1).
const LOSS_PENALTY_TI = new TweenInfo(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// BaseCash growth — red-tinge style matching the in-game multiplier label.
const BASE_CASH_MAX_SIZE_INCREASE = 40;
const BASE_CASH_TARGET_COLOR = new Color3(1, 0.25, 0.25);

// Floating chunk: spawn on the origin, disperse in a random direction, hold,
// then fly to the target. Same feel as the in-game floating labels.
const FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate";
const FLOATING_FLY_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FLOATING_DISPERSE_TI = new TweenInfo(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out);
const FLOATING_DISPERSE_MIN = 70; // px
const FLOATING_DISPERSE_MAX = 130; // px
const FLOATING_HOLD = 0.12; // pause between dispersion and fly-to-target

// Phase 4 — after the spray, the whole BaseCashText label flies to the HUD money.
const FINAL_MOVE_DELAY = 0.45; // extra pause after the chunks land, before the label flies
const BASE_CASH_FLY_TI = new TweenInfo(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// ── Formatting ────────────────────────────────────────────────────────────────

// 2 décimales (0.01 près) — pas d'arrondi, pour afficher EXACTEMENT le multiplicateur
// verrouillé au claim (la popup de fin reçoit `claimedMultiplier`, voir §6.3).
function formatMultiplier(value: number): string {
	return `${string.format("%.2f", value)}x`;
}

function formatCash(value: number): string {
	return FormatCash(value);
}

// ── Floating chunk ──────────────────────────────────────────────────────────────

interface FloatingHandlers {
	onSpawn: () => void;
	onArrived: () => void;
}

let cachedTemplate: Frame | undefined;
function getFloatingTemplate(): Frame | undefined {
	if (cachedTemplate) return cachedTemplate;
	const found = ReplicatedStorage.FindFirstChild(FLOATING_TEMPLATE_NAME);
	if (found?.IsA("Frame")) cachedTemplate = found;
	return cachedTemplate;
}

// Spawns a floating "+amount" on `origin`, disperses it, then flies it to
// `target`. onSpawn fires immediately; onArrived fires when the fly completes.
function spawnFloatingChunk(
	parent: ScreenGui,
	amount: number,
	origin: GuiObject,
	target: GuiObject,
	handlers: FloatingHandlers,
): void {
	const template = getFloatingTemplate();
	if (!template) {
		// Template missing — still fire callbacks so the pipeline stays coherent.
		handlers.onSpawn();
		task.delay(FLOATING_DISPERSE_TI.Time + FLOATING_HOLD + FLOATING_FLY_TI.Time, () => handlers.onArrived());
		return;
	}

	const screenSize = parent.AbsoluteSize;
	if (screenSize.X === 0) {
		handlers.onSpawn();
		handlers.onArrived();
		return;
	}

	const frame = template.Clone();
	frame.Name = "EndGameFloatingChunk";
	frame.AnchorPoint = new Vector2(0.5, 0.5);
	frame.ZIndex = 30;
	frame.Visible = true;
	frame.Parent = parent;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${formatCash(amount)}`;

	// 1. Spawn on the origin's center (at native size — no spawn bump).
	const originCenter = origin.AbsolutePosition.add(origin.AbsoluteSize.div(2));
	frame.Position = new UDim2(0, originCenter.X, 0, originCenter.Y);

	handlers.onSpawn();

	// 2. Disperse in a random direction.
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
		// 3. Brief hold so the eye registers where it landed.
		task.delay(FLOATING_HOLD, () => {
			// Target re-read at fly-time — handles layout shifts mid-animation.
			const targetCenter = target.AbsolutePosition.add(target.AbsoluteSize.div(2));
			const targetPos = new UDim2(0, targetCenter.X, 0, targetCenter.Y);

			// 4. Fly to the target.
			const fly = TweenService.Create(frame, FLOATING_FLY_TI, { Position: targetPos });
			fly.Completed.Connect(() => {
				frame.Destroy();
				handlers.onArrived();
			});
			fly.Play();
		});
	});
}

// ── Blocking value/size/color tween for BaseCashText ─────────────────────────────

// Tweens BaseCashText's value (via a NumberValue proxy so it re-formats every
// frame), text size and color from start to end in parallel, blocking until done,
// then snaps to the exact end values to avoid float drift.
function animateCash(
	label: TextLabel,
	startValue: number,
	endValue: number,
	startSize: number,
	endSize: number,
	startColor: Color3,
	endColor: Color3,
	ti: TweenInfo,
): void {
	label.Text = formatCash(startValue);
	label.TextSize = startSize;
	label.TextColor3 = startColor;

	const proxy = new Instance("NumberValue");
	proxy.Value = startValue;
	const conn = proxy.Changed.Connect((v) => {
		label.Text = formatCash(v);
	});

	TweenService.Create(proxy, ti, { Value: endValue }).Play();
	const styleTween = TweenService.Create(label, ti, { TextSize: endSize, TextColor3: endColor });
	styleTween.Play();
	styleTween.Completed.Wait();

	conn.Disconnect();
	proxy.Destroy();
	label.Text = formatCash(endValue);
	label.TextSize = endSize;
	label.TextColor3 = endColor;
}

// ── Phase 1: MultiplierText flies into BaseCashText, then disappears ─────────────

function mergeMultiplierIntoBaseCash(multiplierText: TextLabel, baseCashText: TextLabel): void {
	// Both labels share the same parent + anchor (0.5, 0.5), so copying Position
	// lands the multiplier squarely on the base cash.
	const tween = TweenService.Create(multiplierText, MULTIPLIER_MERGE_TI, { Position: baseCashText.Position });
	tween.Play();
	tween.Completed.Wait();
	multiplierText.Visible = false;
}

// ── Phase 4: the whole BaseCashText label flies to the HUD money ─────────────────

// Clones BaseCashText to the ScreenGui (so the original resets cleanly), hides the
// original, and flies the clone onto the HUD money. Cosmetic — the chunks already
// banked the cash. onArrived fires when the clone lands.
function flyBaseCashToHud(parent: ScreenGui, sourceLabel: TextLabel, target: GuiObject, onArrived: () => void): void {
	if (parent.AbsoluteSize.X === 0) {
		sourceLabel.Visible = false;
		onArrived();
		return;
	}

	const srcCenter = sourceLabel.AbsolutePosition.add(sourceLabel.AbsoluteSize.div(2));
	const absSize = sourceLabel.AbsoluteSize;

	const clone = sourceLabel.Clone();
	clone.Name = "EndGameBaseCashFly";
	clone.AnchorPoint = new Vector2(0.5, 0.5);
	clone.Size = new UDim2(0, absSize.X, 0, absSize.Y);
	clone.Position = new UDim2(0, srcCenter.X, 0, srcCenter.Y);
	clone.ZIndex = 32;
	clone.Visible = true;
	clone.Parent = parent;

	// The clone carries the visual to the HUD; hide the original immediately.
	sourceLabel.Visible = false;

	const targetCenter = target.AbsolutePosition.add(target.AbsoluteSize.div(2));
	const fly = TweenService.Create(clone, BASE_CASH_FLY_TI, {
		Position: new UDim2(0, targetCenter.X, 0, targetCenter.Y),
		TextSize: initialBaseCashSize ?? clone.TextSize,
	});
	fly.Completed.Connect(() => {
		clone.Destroy();
		onArrived();
	});
	fly.Play();
}

// ── Orchestrator ────────────────────────────────────────────────────────────────

interface EndGameRefs {
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
	return { multiplierText, baseCashText, screenGui };
}

// First-call snapshots — capture the Studio-authored state so every run resets to
// the same baseline instead of compounding the previous run's growth/move.
let initialBaseCashSize: number | undefined;
let initialBaseCashColor: Color3 | undefined;
let initialMultiplierPosition: UDim2 | undefined;
let initialMultiplierTransparency: number | undefined;

// Runs the full ButtonFinishGame animation, then calls onComplete().
// Safe to call from a regular task (uses task.wait internally).
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

	if (initialBaseCashSize === undefined) initialBaseCashSize = baseCashText.TextSize;
	if (initialBaseCashColor === undefined) initialBaseCashColor = baseCashText.TextColor3;
	if (initialMultiplierPosition === undefined) initialMultiplierPosition = multiplierText.Position;
	if (initialMultiplierTransparency === undefined) initialMultiplierTransparency = multiplierText.TextTransparency;
	const baseSize = initialBaseCashSize;
	const baseColor = initialBaseCashColor;

	// ── Reset MultiplierText — match the in-game label's last appearance ──────────
	const snapshot = MultiplierVisuals.getLast();
	const inGameSize = snapshot?.size ?? multiplierText.TextSize;
	const inGameColor = snapshot?.color ?? multiplierText.TextColor3;
	multiplierText.Position = initialMultiplierPosition;
	multiplierText.TextTransparency = initialMultiplierTransparency;
	multiplierText.TextSize = inGameSize;
	multiplierText.TextColor3 = inGameColor;
	multiplierText.Text = formatMultiplier(multiplier);
	multiplierText.Visible = true;

	// ── Reset BaseCashText to its base value/look ─────────────────────────────────
	baseCashText.Text = formatCash(baseCash);
	baseCashText.TextSize = baseSize;
	baseCashText.TextColor3 = baseColor;
	baseCashText.Visible = true;

	// ── "Finish" flash (blocks through fade-in + hold) ───────────────────────────
	InformationText.show(FINISH_TEXT);
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME);

	// ── Kill penalty: shrink BaseCashText value + size before the count-up ────────
	let effectiveBaseCash = baseCash;
	let effectiveBaseSize = baseSize;
	if (lossMultiplier < 1) {
		effectiveBaseCash = baseCash * lossMultiplier;
		effectiveBaseSize = baseSize * lossMultiplier;
		animateCash(baseCashText, baseCash, effectiveBaseCash, baseSize, effectiveBaseSize, baseColor, baseColor, LOSS_PENALTY_TI);
	}

	// ── Phase 1: MultiplierText merges into BaseCashText and disappears ───────────
	mergeMultiplierIntoBaseCash(multiplierText, baseCashText);

	// ── Phase 2: BaseCashText counts up by the in-game multiplier ─────────────────
	// EffectiveBaseCash already includes every money multiplier (rebirth + tier +
	// community), so the start number shows the boost — no separate rebirth phase.
	const totalEarn = effectiveBaseCash * multiplier;
	const grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE;
	animateCash(
		baseCashText,
		effectiveBaseCash,
		totalEarn,
		effectiveBaseSize,
		grownSize,
		baseColor,
		BASE_CASH_TARGET_COLOR,
		BASE_CASH_COUNTUP_TI,
	);

	// ── Phase 3: spray N floating texts into the money HUD ────────────────────────
	const moneyParent = InGameUIController.getMoneyParent();
	const n = FLOATING_TEXT_COUNT;
	const chunk = n > 0 ? totalEarn / n : 0;

	const finishReset = () => {
		// Leave BaseCashText hidden but reset to the Studio baseline for next run.
		baseCashText.Visible = false;
		if (initialBaseCashSize !== undefined) baseCashText.TextSize = initialBaseCashSize;
		if (initialBaseCashColor !== undefined) baseCashText.TextColor3 = initialBaseCashColor;
	};

	// No HUD target / nothing to spray → deposit visually and finish.
	if (!moneyParent || n <= 0 || totalEarn <= 0) {
		if (totalEarn > 0) MoneyDisplay.addVisual(totalEarn);
		finishReset();
		onComplete();
		return;
	}

	let arrived = 0;
	for (let i = 1; i <= n; i++) {
		const isLast = i === n;
		const remaining = isLast ? 0 : totalEarn - i * chunk;
		spawnFloatingChunk(screenGui, chunk, baseCashText, moneyParent, {
			onSpawn: () => {
				// Floating text leaving drops BaseCashText by one chunk (value + size).
				baseCashText.Text = formatCash(remaining);
				const ratio = totalEarn > 0 ? remaining / totalEarn : 0;
				baseCashText.TextSize = baseSize + (grownSize - baseSize) * ratio;
				baseCashText.TextColor3 = baseColor.Lerp(BASE_CASH_TARGET_COLOR, ratio);
				if (isLast) baseCashText.Visible = false;
			},
			onArrived: () => {
				MoneyDisplay.addVisual(chunk);
				arrived += 1;
				if (arrived >= n) {
					finishReset();
					task.delay(0.2, onComplete);
				}
			},
		});
		task.wait(FLOATING_TEXT_INTERVAL);
	}
}
