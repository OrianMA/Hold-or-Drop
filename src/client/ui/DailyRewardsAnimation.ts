import { TweenService } from "@rbxts/services";
import { FormatCash } from "shared/NumberFormat";
import { playCashSound } from "client/audio/CashSound";

// Opening sequence of the DailyRewards popup. Pure presentation — it only writes
// what DailyRewardsBehavior already computed, and every value it touches is captured
// on the first run and restored by stop(), so nothing authored in Studio is lost.
//
// Sequence (fast on purpose — the popup must not feel like a cutscene):
//   1. every row cascades in from the top, staggered top → bottom      (~0.4s)
//   2. Base cash is already written, it never animates
//   3. the total counts up 0 → base × multiplier                       (0.5s)
//   4. LAST, after a longer beat, the day counter climbs from N−1 → N while the
//      label pops bigger, flashes and plays the cash sound, then settles back to
//      its authored size + colour                                      (0.45s)
//      N−1 means a first day (or a broken streak) visibly counts 0 → 1.

const ENTRANCE_OFFSET = 24; // px above the resting position each row starts at
const ENTRANCE_TI = new TweenInfo(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const ENTRANCE_STAGGER = 0.04;

const TOTAL_COUNT_TI = new TweenInfo(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
// Breath between the total and the multiplier pop. Deliberately long: the day counter
// is the payoff of the whole popup, it needs a beat of silence before it fires.
const MULT_GAP = 0.45;
const MULT_COUNT_TI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const MULT_POP_TI = new TweenInfo(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const MULT_SETTLE_TI = new TweenInfo(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const MULT_POP_SCALE = 1.35;
const MULT_FLASH_COLOR = new Color3(1, 0.84, 0.25); // gold, lerped back to the authored colour

export interface DailyRewardsRefs {
	popup: GuiObject;
	rows: GuiObject[]; // every element that cascades in (header included)
	totalLabel: TextLabel;
	multiplierLabel: TextLabel;
}

export interface DailyRewardsValues {
	baseCash: number;
	multiplier: number;
	// False when today's reward is already claimed: the popup still cascades in, but
	// the counters snap to their final value instead of replaying the reveal.
	animateCounters: boolean;
}

// alpha 1 = fully visible (authored value), alpha 0 = fully transparent.
type Fade = (alpha: number) => void;

interface Row {
	instance: GuiObject;
	position: UDim2; // authored position, restored after the slide
	fades: Fade[];
}

// A row's transparency is driven through one proxy per row rather than one tween per
// property — a row is a label + its stroke + sometimes a button, and animating them
// separately would multiply the tweens for no visual gain.
function collectFades(root: GuiObject): Fade[] {
	const fades: Fade[] = [];

	const add = (instance: Instance): void => {
		if (instance.IsA("UIStroke")) {
			const authored = instance.Transparency;
			fades.push((alpha) => {
				instance.Transparency = 1 - (1 - authored) * alpha;
			});
			return;
		}
		if (instance.IsA("GuiObject")) {
			const background = instance.BackgroundTransparency;
			fades.push((alpha) => {
				instance.BackgroundTransparency = 1 - (1 - background) * alpha;
			});
		}
		if (instance.IsA("TextLabel") || instance.IsA("TextButton")) {
			const text = instance.TextTransparency;
			fades.push((alpha) => {
				instance.TextTransparency = 1 - (1 - text) * alpha;
			});
		}
		if (instance.IsA("ImageLabel") || instance.IsA("ImageButton")) {
			const image = instance.ImageTransparency;
			fades.push((alpha) => {
				instance.ImageTransparency = 1 - (1 - image) * alpha;
			});
		}
	};

	add(root);
	for (const descendant of root.GetDescendants()) add(descendant);
	return fades;
}

// Cascade order = the authored vertical layout, so re-arranging the popup in Studio
// re-orders the animation on its own. Parent weight first (Header → Body → Buttons),
// then the row's own Y scale inside that parent.
function sortKey(row: GuiObject): number {
	const parentName = row.Parent?.Name ?? "";
	const weight = parentName === "Body" ? 1 : row.Name === "Header" ? 0 : 2;
	return weight + row.Position.Y.Scale;
}

let generation = 0;
let rows: Row[] | undefined;
let multiplierScale: UIScale | undefined;
let multiplierColor: Color3 | undefined;
const proxies: NumberValue[] = [];

// One-shot capture of everything the sequence mutates. Done on the first play, when
// the popup still holds exactly what Studio authored.
function capture(refs: DailyRewardsRefs): Row[] {
	if (rows) return rows;

	// The multiplier pops through a UIScale so its authored Size/Position stay intact.
	// Re-anchored to its centre (with a compensating Position) so it grows both ways
	// instead of pushing down onto the title below — visually identical at rest.
	const label = refs.multiplierLabel;
	if (label.AnchorPoint.Y === 0) {
		label.AnchorPoint = new Vector2(label.AnchorPoint.X, 0.5);
		const p = label.Position;
		label.Position = new UDim2(p.X.Scale, p.X.Offset, p.Y.Scale + label.Size.Y.Scale / 2, p.Y.Offset);
	}
	multiplierColor = label.TextColor3;
	let scale = label.FindFirstChildOfClass("UIScale");
	if (!scale) {
		scale = new Instance("UIScale");
		scale.Parent = label;
	}
	multiplierScale = scale;

	// NB: the re-anchor above MUST happen before the rows record their positions —
	// the cascade tweens each row back to what it captured here.
	const captured: Row[] = [];
	refs.rows.forEach((instance) => {
		captured.push({ instance, position: instance.Position, fades: collectFades(instance) });
	});
	// Stable sort: RobloxLua's table.sort isn't stable, so ties (the two buttons, same
	// Y) are broken by their index in the authored list.
	const indexOf = new Map<GuiObject, number>();
	captured.forEach((row, index) => indexOf.set(row.instance, index));
	captured.sort((a, b) => {
		const ka = sortKey(a.instance);
		const kb = sortKey(b.instance);
		if (ka !== kb) return ka < kb;
		return (indexOf.get(a.instance) ?? 0) < (indexOf.get(b.instance) ?? 0);
	});

	rows = captured;
	return captured;
}

function applyFades(row: Row, alpha: number): void {
	for (const fade of row.fades) fade(alpha);
}

// Tweens a number through a proxy NumberValue (same idiom as MoneyDisplay) and
// renders each step through `format`.
function countTo(id: number, from: number, to: number, info: TweenInfo, format: (value: number) => void): void {
	const proxy = new Instance("NumberValue");
	proxy.Value = from;
	proxies.push(proxy);
	format(from);

	// The generation guard matters on every step: a dropped sequence's tween keeps
	// running on its (already released) proxy and must not write to the labels.
	proxy.Changed.Connect((value) => {
		if (id === generation) format(value);
	});
	const tween = TweenService.Create(proxy, info, { Value: to });
	tween.Completed.Connect(() => {
		if (id === generation) format(to);
		release(proxy);
	});
	tween.Play();
}

function release(proxy: NumberValue): void {
	const index = proxies.indexOf(proxy);
	if (index >= 0) proxies.remove(index);
	proxy.Destroy();
}

function clearProxies(): void {
	for (const proxy of [...proxies]) proxy.Destroy();
	while (proxies.size() > 0) proxies.pop();
}

export const DailyRewardsAnimation = {
	// Plays the whole opening sequence. Safe to call again while one is running —
	// the previous sequence is dropped (generation guard) and its labels rewritten.
	play(refs: DailyRewardsRefs, values: DailyRewardsValues): void {
		const id = ++generation;
		clearProxies();

		const captured = capture(refs);
		const total = math.floor(values.baseCash * values.multiplier);

		const renderTotal = (value: number): void => {
			refs.totalLabel.Text = `$${FormatCash(math.floor(value))}`;
		};
		const renderMultiplier = (value: number): void => {
			refs.multiplierLabel.Text = `${math.floor(value)}x`;
		};

		// 1. every row starts transparent, one notch above its resting position.
		captured.forEach((row) => {
			applyFades(row, 0);
			row.instance.Position = new UDim2(
				row.position.X.Scale,
				row.position.X.Offset,
				row.position.Y.Scale,
				row.position.Y.Offset - ENTRANCE_OFFSET,
			);
		});

		captured.forEach((row, index) => {
			task.delay(index * ENTRANCE_STAGGER, () => {
				if (id !== generation || row.instance.Parent === undefined) return;
				const proxy = new Instance("NumberValue");
				proxies.push(proxy);
				proxy.Changed.Connect((alpha) => {
					if (id === generation) applyFades(row, alpha);
				});
				const fade = TweenService.Create(proxy, ENTRANCE_TI, { Value: 1 });
				fade.Completed.Connect(() => {
					if (id === generation) applyFades(row, 1);
					release(proxy);
				});
				fade.Play();
				TweenService.Create(row.instance, ENTRANCE_TI, { Position: row.position }).Play();
			});
		});

		const entranceEnd = (captured.size() - 1) * ENTRANCE_STAGGER + ENTRANCE_TI.Time;

		// Already claimed → no reveal, the numbers are just there.
		if (!values.animateCounters) {
			renderTotal(total);
			renderMultiplier(values.multiplier);
			return;
		}

		// 2. the total counts up from zero.
		// The day counter starts one day BEHIND, so a first day — or a streak that was
		// just lost — is seen climbing 0 → 1 rather than sitting on its final value.
		const multiplierFrom = math.max(0, values.multiplier - 1);
		renderTotal(0);
		renderMultiplier(multiplierFrom);
		task.delay(entranceEnd, () => {
			if (id !== generation) return;
			countTo(id, 0, total, TOTAL_COUNT_TI, renderTotal);
		});

		// 3. LAST, the multiplier: pops bigger + flashes gold while it counts, then
		//    settles back to the authored size and colour.
		task.delay(entranceEnd + TOTAL_COUNT_TI.Time + MULT_GAP, () => {
			if (id !== generation || !multiplierScale) return;

			refs.multiplierLabel.TextColor3 = MULT_FLASH_COLOR;
			multiplierScale.Scale = 1;
			playCashSound(); // même son d'argent que le claim, sur le pic de l'animation
			TweenService.Create(multiplierScale, MULT_POP_TI, { Scale: MULT_POP_SCALE }).Play();
			countTo(id, multiplierFrom, values.multiplier, MULT_COUNT_TI, renderMultiplier);

			task.delay(MULT_POP_TI.Time, () => {
				if (id !== generation || !multiplierScale) return;
				TweenService.Create(multiplierScale, MULT_SETTLE_TI, { Scale: 1 }).Play();
				if (multiplierColor !== undefined) {
					TweenService.Create(refs.multiplierLabel, MULT_SETTLE_TI, {
						TextColor3: multiplierColor,
					}).Play();
				}
			});
		});
	},

	// Drops a running sequence and restores the popup to its resting look, so a
	// close mid-animation never leaves a half-faded row behind.
	stop(refs: DailyRewardsRefs, values: DailyRewardsValues): void {
		generation += 1;
		clearProxies();

		if (rows) {
			for (const row of rows) {
				applyFades(row, 1);
				row.instance.Position = row.position;
			}
		}
		if (multiplierScale) multiplierScale.Scale = 1;
		if (multiplierColor !== undefined) refs.multiplierLabel.TextColor3 = multiplierColor;

		refs.totalLabel.Text = `$${FormatCash(math.floor(values.baseCash * values.multiplier))}`;
		refs.multiplierLabel.Text = `${values.multiplier}x`;
	},
};
