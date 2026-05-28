import { Players, TweenService } from "@rbxts/services";
import { MainUIController } from "client/ui/MainUIController";
import { FormatCash } from "shared/NumberFormat";

// Renders the local player's Money attribute into a TextLabel named "MoneyText"
// sitting under MoneyParent inside MainUI. The attribute is set by the server
// (PlayerDataService) and auto-replicates to this client.
//
// Updates animate via a NumberValue proxy tweened with TweenService — the
// label text is re-formatted on every Changed step, so the player sees the
// number visibly ticking up from the previous balance to the new one. This
// pattern is robust to mid-flight interruption (e.g. earning more money while
// the previous tween is still running): we cancel, restart from the current
// visual value, and head toward the new target.

const ATTRIBUTE = "Money";
const LABEL_NAME = "MoneyText";

// Duration of the "count-up" animation. Quad-Out feels punchier than Linear —
// fast start, decelerating finish, matching how popular idle games render
// reward deltas.
const TWEEN_INFO = new TweenInfo(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

function findLabel(): TextLabel | undefined {
	const moneyParent = MainUIController.getMoneyParent();
	if (!moneyParent) return undefined;
	const found = moneyParent.FindFirstChild(LABEL_NAME, true);
	return found?.IsA("TextLabel") ? found : undefined;
}

export function init(): void {
	const player = Players.LocalPlayer;

	// Persistent proxy + the value we last rendered. We tween the proxy and
	// mirror its value into the label on every Changed step.
	const proxy = new Instance("NumberValue");
	let displayValue = 0;
	let initialized = false;
	let activeTween: Tween | undefined;
	let proxyConn: RBXScriptConnection | undefined;

	proxy.Changed.Connect((v) => {
		displayValue = v;
		const label = findLabel();
		if (label) label.Text = FormatCash(math.floor(v));
	});

	const refresh = () => {
		const target = (player.GetAttribute(ATTRIBUTE) as number | undefined) ?? 0;

		// First update on join (or first time the label appears): snap, no tween,
		// so the HUD doesn't count up from 0 every time the player loads in.
		if (!initialized) {
			initialized = true;
			proxy.Value = target;
			displayValue = target;
			const label = findLabel();
			if (label) label.Text = FormatCash(target);
			return;
		}

		// Already at target → nothing to animate. Still cancel any in-flight
		// tween so it doesn't overshoot the (now stale) previous target.
		if (math.floor(displayValue) === target) {
			if (activeTween !== undefined) {
				activeTween.Cancel();
				activeTween = undefined;
			}
			proxy.Value = target;
			return;
		}

		// Cancel any in-flight tween and restart from where we *visually* are,
		// not where the previous tween was supposed to land. Without this, a
		// quick succession of credits would jump-cut to the latest target.
		if (activeTween !== undefined) {
			activeTween.Cancel();
			activeTween = undefined;
		}
		if (proxyConn !== undefined) {
			proxyConn.Disconnect();
			proxyConn = undefined;
		}

		proxy.Value = displayValue;

		activeTween = TweenService.Create(proxy, TWEEN_INFO, { Value: target });
		const tween = activeTween;
		// On completion, snap to the exact target — float interpolation can
		// leave a 1-unit gap that would render as e.g. "$1999" instead of "$2K".
		const completedConn = tween.Completed.Connect(() => {
			completedConn.Disconnect();
			if (activeTween === tween) {
				activeTween = undefined;
				proxy.Value = target;
				const label = findLabel();
				if (label) label.Text = FormatCash(target);
			}
		});
		tween.Play();
	};

	refresh();
	player.GetAttributeChangedSignal(ATTRIBUTE).Connect(refresh);

	// Label may not exist yet on first frame — re-render on new descendants
	const gui = player.WaitForChild("PlayerGui") as PlayerGui;
	gui.DescendantAdded.Connect((desc) => {
		if (desc.Name === LABEL_NAME && desc.IsA("TextLabel")) {
			// Label just appeared — render current value snapped (no tween),
			// otherwise it would animate from 0 to current on first display.
			desc.Text = FormatCash(math.floor(displayValue));
		}
	});
}
