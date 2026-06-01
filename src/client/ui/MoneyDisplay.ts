import { Players, TweenService } from "@rbxts/services";
import { MainUIController } from "client/ui/MainUIController";
import { FormatCash } from "shared/NumberFormat";

// Renders the local player's Money attribute into a TextLabel named "MoneyText"
// sitting under MoneyParent inside MainUI. The attribute is set by the server
// (PlayerDataService) and auto-replicates to this client.
//
// Updates animate via a NumberValue proxy tweened with TweenService — the label
// text is re-formatted on every Changed step, so the player sees the number
// visibly ticking from the previous balance to the new one. Robust to mid-flight
// interruption (e.g. earning more while a tween runs): we cancel, restart from
// the current visual value, and head toward the new target.
//
// `addVisual` lets other UI (e.g. the end-game payout animation) drive the HUD
// up incrementally for cosmetic effect. The Money attribute stays the source of
// truth — when the server credit lands, refresh() reconciles to the same value
// with no visible jump.

const ATTRIBUTE = "Money";
const LABEL_NAME = "MoneyText";

// Duration of the "count-up" animation. Quad-Out feels punchier than Linear.
const TWEEN_INFO = new TweenInfo(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// Persistent proxy + the value we last rendered. We tween the proxy and mirror
// its value into the label on every Changed step. `currentTarget` is the value
// the proxy is currently heading toward (attribute- or addVisual-driven).
let proxy: NumberValue | undefined;
let displayValue = 0;
let currentTarget = 0;
let initialized = false;
let activeTween: Tween | undefined;

function findLabel(): TextLabel | undefined {
	const moneyParent = MainUIController.getMoneyParent();
	if (!moneyParent) return undefined;
	const found = moneyParent.FindFirstChild(LABEL_NAME, true);
	return found?.IsA("TextLabel") ? found : undefined;
}

function render(value: number): void {
	const label = findLabel();
	if (label) label.Text = FormatCash(math.floor(value));
}

// Cancel any in-flight tween and head from where we *visually* are toward
// `target`. Snaps instead of tweening when we're already there.
function tweenTo(target: number): void {
	currentTarget = target;
	if (!proxy) return;

	if (activeTween !== undefined) {
		activeTween.Cancel();
		activeTween = undefined;
	}

	if (math.floor(displayValue) === math.floor(target)) {
		proxy.Value = target;
		return;
	}

	proxy.Value = displayValue;
	const tween = TweenService.Create(proxy, TWEEN_INFO, { Value: target });
	activeTween = tween;
	const completed = tween.Completed.Connect(() => {
		completed.Disconnect();
		if (activeTween === tween) {
			activeTween = undefined;
			if (proxy) proxy.Value = target;
			render(target);
		}
	});
	tween.Play();
}

function refresh(): void {
	const target = (Players.LocalPlayer.GetAttribute(ATTRIBUTE) as number | undefined) ?? 0;

	// First update on join: snap, no tween, so the HUD doesn't count up from 0
	// every time the player loads in.
	if (!initialized) {
		initialized = true;
		if (proxy) proxy.Value = target;
		displayValue = target;
		currentTarget = target;
		render(target);
		return;
	}

	tweenTo(target);
}

export const MoneyDisplay = {
	init(): void {
		const player = Players.LocalPlayer;

		proxy = new Instance("NumberValue");
		proxy.Changed.Connect((v) => {
			displayValue = v;
			render(v);
		});

		refresh();
		player.GetAttributeChangedSignal(ATTRIBUTE).Connect(refresh);

		// Label may not exist yet on first frame — re-render on new descendants.
		const gui = player.WaitForChild("PlayerGui") as PlayerGui;
		gui.DescendantAdded.Connect((desc) => {
			if (desc.Name === LABEL_NAME && desc.IsA("TextLabel")) {
				desc.Text = FormatCash(math.floor(displayValue));
			}
		});
	},

	// Cosmetic: bump the displayed balance up by `amount` (count-up tween). The
	// real Money attribute remains authoritative; refresh() reconciles when the
	// server credit lands.
	addVisual(amount: number): void {
		tweenTo(currentTarget + amount);
	},
};
