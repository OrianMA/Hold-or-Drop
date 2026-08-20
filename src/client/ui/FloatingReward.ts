import { Players, ReplicatedStorage, TweenService } from "@rbxts/services";
import { Events } from "shared/Event";
import { InGameUIController } from "client/ui/InGameUIController";
import { MoneyDisplay } from "client/ui/MoneyDisplay";
import { FloatingCash } from "client/ui/FloatingCash";
import { FormatCash } from "shared/NumberFormat";

// ── Single "+amount" reward text ────────────────────────────────────────────────
//
// One gain, one label: pops in the middle of the screen, jumps, holds so the eye
// registers the amount, then ends one of two ways:
//
//   "fly"  — flies into the money HUD. Used by the losing-explosion consolation
//            (LossRewardBehavior), which re-shows the HUD first.
//   "fade" — fades out on the spot. Used when a payout is flushed because another
//            popup opened (EndGamePayoutFlushEvent): that popup hid the HUD, so
//            there is no visible counter to fly into.
//
// Both endings bank on disappearance: MoneyDisplay.addVisual (count-up + money SFX)
// plus EndGameFinishedEvent so the server credits the real Money through the shared
// pendingEarned path. Banking is skipped when a rebirth invalidated the run
// (FloatingCash generation), exactly like the end-game payout chunks.
//
// `showAlreadyCredited` is the same text with the banking removed — for gains the
// server has ALREADY credited (the daily reward, §6.25). Banking there would count the
// money a second time on screen and fire an end-game event that has nothing to do with
// this gain.

// Reuse the template the end-game payout sprays (a Frame holding an "Amount"
// TextLabel), preloaded in ReplicatedStorage.
const FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate";

// Frame name kept in sync with FloatingCash.FLOATING_FRAME_NAMES so a rebirth
// destroys the text mid-flight.
const FRAME_NAME = "LossRewardFloatingText";

const JUMP_HEIGHT = 90; // px the text jumps up before flying / fading
const JUMP_TI = new TweenInfo(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out);
const HOLD = 0.7; // pause at the top so the eye registers the amount
const FLY_TI = new TweenInfo(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
const FADE_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

export type RewardEnding = "fly" | "fade";

// How many reward texts are currently on screen. Lets callers avoid stacking a
// second one on top of a gain the player is already reading.
let activeCount = 0;

let cachedTemplate: Frame | undefined;
function getTemplate(): Frame | undefined {
	if (cachedTemplate) return cachedTemplate;
	const found = ReplicatedStorage.FindFirstChild(FLOATING_TEMPLATE_NAME);
	if (found?.IsA("Frame")) cachedTemplate = found;
	return cachedTemplate;
}

function getScreenGui(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

// Tweens every drawable part of the cloned template to fully transparent, whatever
// the Studio author put inside it (labels, strokes, images, backgrounds).
function fadeOut(frame: Frame, onDone: () => void): void {
	const parts: Instance[] = [frame];
	for (const desc of frame.GetDescendants()) parts.push(desc);

	for (const part of parts) {
		if (part.IsA("TextLabel")) {
			TweenService.Create(part, FADE_TI, {
				TextTransparency: 1,
				TextStrokeTransparency: 1,
				BackgroundTransparency: 1,
			}).Play();
		} else if (part.IsA("ImageLabel")) {
			TweenService.Create(part, FADE_TI, { ImageTransparency: 1, BackgroundTransparency: 1 }).Play();
		} else if (part.IsA("GuiObject")) {
			TweenService.Create(part, FADE_TI, { BackgroundTransparency: 1 }).Play();
		} else if (part.IsA("UIStroke")) {
			TweenService.Create(part, FADE_TI, { Transparency: 1 }).Play();
		}
	}

	task.delay(FADE_TI.Time, onDone);
}

// Banks the cash and tells the server to credit it. Skips banking if a rebirth
// cancelled this run (gen went stale) — the server pending credit is cleared too.
function bank(amount: number, gen: number, credit: boolean, onBanked?: () => void): void {
	activeCount = math.max(activeCount - 1, 0);
	if (credit && !FloatingCash.isStale(gen)) {
		MoneyDisplay.addVisual(amount); // count-up + money SFX
		Events.EndGameFinishedEvent.FireServer(); // server credits pendingEarned, reconciles HUD
	}
	onBanked?.();
}

function spawn(amount: number, ending: RewardEnding, credit: boolean, onBanked?: () => void): void {
	const template = getTemplate();
	const screenGui = getScreenGui();
	const runGen = FloatingCash.current();
	const flyTarget = ending === "fly" ? InGameUIController.getMoneyParent() : undefined;

	activeCount += 1;

	// No template / no laid-out screen / no fly target — still bank so the credit lands.
	if (!template || !screenGui || screenGui.AbsoluteSize.X === 0 || (ending === "fly" && !flyTarget)) {
		bank(amount, runGen, credit, onBanked);
		return;
	}

	const center = screenGui.AbsoluteSize.div(2);

	const frame = template.Clone();
	frame.Name = FRAME_NAME;
	frame.AnchorPoint = new Vector2(0.5, 0.5);
	frame.ZIndex = 30;
	frame.Position = new UDim2(0, center.X, 0, center.Y);
	frame.Visible = true;
	frame.Parent = screenGui;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${FormatCash(amount)}`;

	const finish = () => {
		frame.Destroy();
		bank(amount, runGen, credit, onBanked);
	};

	// 1. Jump up.
	const jump = TweenService.Create(frame, JUMP_TI, {
		Position: new UDim2(0, center.X, 0, center.Y - JUMP_HEIGHT),
	});
	jump.Completed.Connect(() => {
		// 2. Brief hold, then the chosen ending.
		task.delay(HOLD, () => {
			// A rebirth may have destroyed the frame while it was holding.
			if (frame.Parent === undefined) {
				bank(amount, runGen, credit, onBanked);
				return;
			}

			if (!flyTarget) {
				fadeOut(frame, finish);
				return;
			}

			// 3. Fly to the money HUD (target re-read at fly-time).
			const targetCenter = flyTarget.AbsolutePosition.add(flyTarget.AbsoluteSize.div(2));
			const fly = TweenService.Create(frame, FLY_TI, {
				Position: new UDim2(0, targetCenter.X, 0, targetCenter.Y),
			});
			fly.Completed.Connect(finish);
			fly.Play();
		});
	});
	jump.Play();
}

export const FloatingReward = {
	// True while a reward text is on screen (or still owes its bank callback).
	isActive(): boolean {
		return activeCount > 0;
	},

	show(amount: number, ending: RewardEnding, onBanked?: () => void): void {
		task.spawn(() => spawn(amount, ending, true, onBanked));
	},

	// Same text, no banking: the amount is already in the player's balance (server-side
	// credit, e.g. the daily reward). Purely a readout of what was just earned.
	showAlreadyCredited(amount: number, ending: RewardEnding): void {
		task.spawn(() => spawn(amount, ending, false));
	},
};
