import { Players, ReplicatedStorage, TweenService } from "@rbxts/services";
import { Events } from "shared/Event";
import { InGameUIController } from "client/ui/InGameUIController";
import { MoneyDisplay } from "client/ui/MoneyDisplay";
import { FloatingCash } from "client/ui/FloatingCash";
import { MusicController } from "client/audio/MusicController";
import { FormatCash } from "shared/NumberFormat";

// ── Losing-explosion consolation ────────────────────────────────────────────────
//
// On a losing explosion there is NO ButtonFinishGame popup (see §6.3). Instead the
// player gets a flat consolation (baseCash / 3, computed server-side) shown as a
// single "+amount" text that pops up in the middle of the screen, holds, then flies
// into the money HUD. On arrival it banks the cash (MoneyDisplay.addVisual — count-up
// + money SFX) and fires EndGameFinishedEvent so the server credits the real Money
// via the shared pendingEarned path (the HUD reconciles with no jump).

// Reuse the same floating template the end-game payout sprays (a Frame holding an
// "Amount" TextLabel), preloaded in ReplicatedStorage.
const FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate";

const JUMP_HEIGHT = 90; // px the text jumps up before flying to the money
const JUMP_TI = new TweenInfo(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out);
const HOLD = 0.7; // pause at the top so the eye registers the amount before it flies off
const FLY_TI = new TweenInfo(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

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

// Banks the cash and tells the server to credit it (shared with the popup path).
// Skips banking if a rebirth cancelled this run (gen went stale) so nothing lands
// after the balance was reset to 0 — the server pending credit is cleared too.
function bank(amount: number, gen: number): void {
	if (!FloatingCash.isStale(gen)) {
		MoneyDisplay.addVisual(amount); // count-up + money SFX
		Events.EndGameFinishedEvent.FireServer(); // server credits pendingEarned, reconciles HUD
	}
	MusicController.resumeBgm(); // run fully over — ease the BGM back in
}

function spawnJumpingText(amount: number): void {
	const moneyParent = InGameUIController.getMoneyParent();
	const template = getTemplate();
	const screenGui = getScreenGui();
	const runGen = FloatingCash.current();

	// No target / template / laid-out screen — still bank the cash so the credit lands.
	if (!moneyParent || !template || !screenGui || screenGui.AbsoluteSize.X === 0) {
		bank(amount, runGen);
		return;
	}

	const center = screenGui.AbsoluteSize.div(2);

	const frame = template.Clone();
	frame.Name = "LossRewardFloatingText";
	frame.AnchorPoint = new Vector2(0.5, 0.5);
	frame.ZIndex = 30;
	frame.Position = new UDim2(0, center.X, 0, center.Y);
	frame.Visible = true;
	frame.Parent = screenGui;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${FormatCash(amount)}`;

	// 1. Jump up.
	const jump = TweenService.Create(frame, JUMP_TI, {
		Position: new UDim2(0, center.X, 0, center.Y - JUMP_HEIGHT),
	});
	jump.Completed.Connect(() => {
		// 2. Brief hold, then fly to the money HUD (target re-read at fly-time).
		task.delay(HOLD, () => {
			const targetCenter = moneyParent.AbsolutePosition.add(moneyParent.AbsoluteSize.div(2));
			const fly = TweenService.Create(frame, FLY_TI, {
				Position: new UDim2(0, targetCenter.X, 0, targetCenter.Y),
			});
			fly.Completed.Connect(() => {
				frame.Destroy();
				bank(amount, runGen);
			});
			fly.Play();
		});
	});
	jump.Play();
}

export function init(): void {
	Events.LossRewardEvent.OnClientEvent.Connect((amount: number) => {
		// The HUD was hidden during gameplay; bring it back so the money is visible
		// (GameResultEvent already stopped the held pose and returned the camera).
		InGameUIController.enable();
		task.spawn(() => spawnJumpingText(amount));
	});
}
