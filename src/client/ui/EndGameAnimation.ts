import { Players, ReplicatedStorage, TweenService } from "@rbxts/services";
import { MultiplierVisuals } from "client/ui/MultiplierVisuals";
import { InGameUIController } from "client/ui/InGameUIController";
import { MoneyDisplay } from "client/ui/MoneyDisplay";
import { FloatingCash } from "client/ui/FloatingCash";
import { InformationText } from "client/ui/InformationText";
import { FormatCash } from "shared/NumberFormat";
import { MONEY_IMAGE, MoneyBurst } from "client/ui/MoneyBurst";
import { CriticalRain, RAIN_IMAGE } from "client/ui/CriticalRain";
import { playBigPayout, playCashSound } from "client/audio/CashSound";
import { PayoutTier, tiersCrossed, topTierIndex } from "client/ui/PayoutTiers";

// ── ButtonFinishGame payout animation ───────────────────────────────────────────
//
// Sequence (after the "Finish" flash + optional kill penalty):
//   0.  Claim bonus (Perfect ×3 / Critical ×10, claimBonus > 1): BaseCashText counts up
//       from the raw base to the boosted base with a golden bump — the bonus multiplies
//       the BASE CASH, never the multiplier, and this phase is what shows it.
//   1.  MultiplierText flies into BaseCashText and disappears.
//   2.  BaseCashText counts up by the in-game multiplier, PAR PALIERS (PayoutTiers) :
//       le count-up est découpé en segments qui s'arrêtent pile sur chaque palier
//       franchi, et chaque arrivée déclenche son son + sa gerbe + sa pluie, de plus
//       en plus fort. C'est ce qui rend l'ampleur du gain lisible en temps réel.
//       EffectiveBaseCash already folds in every money multiplier, so no separate
//       rebirth phase is needed.
//   3.  BaseCashText stays put (showing the full total) and sprays N floating texts
//       toward the money HUD; each arrival banks one chunk of the total, avec un
//       pitch qui monte chunk après chunk (crescendo). Le dernier chunk qui atterrit
//       déclenche la gerbe finale sur le compteur.
//
// `flyBaseCashToHud` / FINAL_MOVE_DELAY décrivent une phase 4 qui n'est PAS branchée :
// la phase 3 masque déjà le label sur son dernier chunk. Code mort conservé tel quel.

// ── Tuning ──────────────────────────────────────────────────────────────────────

const FINISH_TEXT = "Finish";

// Phase 1 — MultiplierText merging into BaseCashText.
const MULTIPLIER_MERGE_TI = new TweenInfo(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// Phase 2 — count-up par paliers (PayoutTiers).
// La durée s'allonge avec le nombre de paliers pour qu'ils aient chacun la place de
// claquer, mais reste PLAFONNÉE : l'écran de fin ne doit pas traîner sur un gros run.
const COUNTUP_BASE_TIME = 0.6; // durée historique, sans palier
const COUNTUP_TIME_PER_TIER = 0.2;
const COUNTUP_MAX_TIME = 1.2;
// Valeur du compteur : linéaire. Chaque segment est court, et un easing par segment
// ferait ralentir/repartir le nombre à chaque palier.
const COUNTUP_VALUE_STYLE = Enum.EasingStyle.Linear;
// Taille + couleur : Quad-Out, sur le MÊME temps que la valeur. Pas de dépassement ici
// — c'est le UIScale qui porte le punch (TextSize est plafonné à 100 par Roblox, un
// dépassement sur la taille serait écrêté pile sur les gros paliers).
const COUNTUP_STYLE_STYLE = Enum.EasingStyle.Quad;

// Pluie des paliers : bande COURTE (une vague qui passe, pas une averse qui traîne) et
// plan de rendu BAS — ButtonFinishGame et BaseCashText sont en ZIndex 1, donc la pluie
// tombe derrière le montant, qui reste lisible.
const TIER_RAIN_BAND = 700;
const TIER_RAIN_Z_INDEX = 0;

// Phase 3 — how many floating texts BaseCashText sprays, and how fast.
// Both tweakable: COUNT splits the total earned into COUNT chunks of
// totalEarn / COUNT; INTERVAL is the delay between each spawn.
const FLOATING_TEXT_COUNT = 8;
const FLOATING_TEXT_INTERVAL = 0.12; // seconds between each floating text
// Plus le run est gros, plus il y a de liasses à encaisser — plafonné pour que la
// rafale ne s'éternise pas (16 × 0.12 s ≈ 2 s).
const FLOATING_TEXT_PER_TIER = 1;
const FLOATING_TEXT_MAX = 16;
// Le pitch du son de dépôt monte de 1 à 1 + CHUNK_PITCH_RISE sur la rafale : les N
// ka-ching deviennent un arpège au lieu d'une répétition.
const CHUNK_PITCH_RISE = 0.25;
// Gerbe jouée sur le compteur quand la dernière liasse atterrit — le dernier "boum".
const FINAL_BURST_BASE = 10;

// Phase 0 — claim bonus (Perfect ×3 / Critical ×10) growing the BASE CASH.
// Le compteur monte en doré (couleur du flash Critical) et le texte gonfle, puis
// redescend à sa taille/couleur de base pour que la phase multiplicateur reparte propre.
const CLAIM_BONUS_TI = new TweenInfo(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const CLAIM_BONUS_SETTLE_TI = new TweenInfo(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const CLAIM_BONUS_COLOR = Color3.fromRGB(255, 200, 60);
const CLAIM_BONUS_SIZE_INCREASE = 30;
const CLAIM_BONUS_HOLD = 0.35; // pause pour lire la nouvelle base avant la suite
const CLAIM_BONUS_BANNER_HOLD = 1.6; // durée du bandeau "BASE CASH ×N" (InformationText)

// Penalty animation when the player died (lossMultiplier < 1).
const LOSS_PENALTY_TI = new TweenInfo(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// BaseCash growth — la TAILLE reste pilotée ici ; la COULEUR, elle, est posée par les
// paliers (PayoutTiers) et non plus par une cible fixe.
// 15 et pas plus : Roblox PLAFONNE TextSize à 100 et le label démarre à 85. Au-delà la
// croissance serait silencieusement écrêtée, et l'agrandissement s'arrêterait au milieu
// du count-up au lieu de suivre le nombre jusqu'au bout.
const BASE_CASH_MAX_SIZE_INCREASE = 15;

// Punch du palier : le UIScale saute à `tier.punch` puis se recale à 1. Instance
// SÉPARÉE du label, donc son tween ne croise jamais celui de la taille/couleur et peut
// se dérouler par-dessus le segment suivant sans le perturber.
const PUNCH_NAME = "EndGamePunch";
const PUNCH_SETTLE_TI = new TweenInfo(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out);

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

// ── Stats du joueur qui calibrent l'escalade ────────────────────────────────────
// Les paliers sont des CENTILES de la distribution de vol du joueur (PayoutTiers), donc
// ils dépendent de sa Rocket Speed ET de sa Resistance. Les deux sont des attributs
// répliqués par PlayerProgressionService — `Resistance` porte déjà la valeur EFFECTIVE
// (game pass inclus), c'est-à-dire celle que le modèle de risque serveur utilise.
function playerStat(name: string, fallback: number): number {
	const value = Players.LocalPlayer.GetAttribute(name) as number | undefined;
	return value ?? fallback;
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
	// Optionnel : courbe SÉPARÉE pour la taille et la couleur, sur la même durée. Sert
	// au count-up par paliers, où le nombre doit monter proprement (linéaire) pendant
	// que la taille dépasse et se cale (Back-Out) — le punch du palier.
	styleTi?: TweenInfo,
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
	const styleTween = TweenService.Create(label, styleTi ?? ti, { TextSize: endSize, TextColor3: endColor });
	styleTween.Play();
	styleTween.Completed.Wait();

	conn.Disconnect();
	proxy.Destroy();
	label.Text = formatCash(endValue);
	label.TextSize = endSize;
	label.TextColor3 = endColor;
}

// ── Phase 2: déclenchement d'un palier ──────────────────────────────────────────

// UIScale du punch, créé à la demande sous BaseCashText et réutilisé ensuite.
function getPunchScale(label: TextLabel): UIScale {
	const existing = label.FindFirstChild(PUNCH_NAME);
	if (existing?.IsA("UIScale")) return existing;
	const scale = new Instance("UIScale");
	scale.Name = PUNCH_NAME;
	scale.Parent = label;
	return scale;
}

// Remet le montant à son échelle normale : un punch encore en vol ne doit pas laisser
// le label gonflé sur l'écran suivant.
function resetPunchScale(label: TextLabel): void {
	const existing = label.FindFirstChild(PUNCH_NAME);
	if (existing?.IsA("UIScale")) existing.Scale = 1;
}

// Tout ce qu'un palier fait claquer : le son (de plus en plus aigu et fort), la gerbe
// de billets qui part du montant, et la pluie qui tombe derrière. Les paliers hauts
// ajoutent le son "gros lot" et une pluie d'or par-dessus la pluie de billets.
function fireTier(tier: PayoutTier, label: TextLabel): void {
	playCashSound({ pitch: tier.pitch, volume: tier.volume });
	if (tier.bigReward) playBigPayout();

	// Saut instantané puis recalage : c'est le "snap" qui se lit comme un impact.
	const punch = getPunchScale(label);
	punch.Scale = tier.punch;
	TweenService.Create(punch, PUNCH_SETTLE_TI, { Scale: 1 }).Play();

	// Même convention de coordonnées que spawnFloatingChunk : les particules sont
	// parentées au ScreenGui et positionnées en offsets locaux.
	const center = label.AbsolutePosition.add(label.AbsoluteSize.div(2));
	MoneyBurst.play(center, { count: tier.burstCount });

	const rain = { count: tier.rainCount, band: TIER_RAIN_BAND, zIndex: TIER_RAIN_Z_INDEX };
	if (tier.ingotDownpour > 0) {
		// Climax d'une grosse escalade : déluge de lingots à la place des billets. Une
		// pluie d'or PURE se lit mieux qu'un mélange, et ça tient sous le plafond de
		// gouttes sans que le déluge ait à évincer sa propre pluie de billets.
		CriticalRain.play(RAIN_IMAGE, { ...rain, count: tier.ingotDownpour });
		return;
	}

	CriticalRain.play(MONEY_IMAGE, rain);
	if (tier.goldRain) {
		CriticalRain.play(RAIN_IMAGE, { ...rain, count: math.floor(tier.rainCount / 2) });
	}
}

// ── Phase 2: découpage du count-up en segments ──────────────────────────────────

interface CountUpSegment {
	value: number; // valeur de cash atteinte à la fin du segment
	tier?: PayoutTier; // palier déclenché à l'arrivée, s'il y en a un
}

// Un tween unique regrouperait toutes les détonations au début : les seuils sont
// géométriques (×100, ×250, ×500) donc l'easing les traverse d'un coup, puis plus rien
// pendant la moitié de l'animation. On découpe donc le count-up en segments qui
// s'arrêtent PILE sur la valeur de chaque palier, et on donne à chacun la même durée —
// l'espacement des détonations est alors régulier par construction.
function buildSegments(
	effectiveBaseCash: number,
	totalEarn: number,
	tiers: PayoutTier[],
): { immediate: PayoutTier[]; segments: CountUpSegment[] } {
	const immediate: PayoutTier[] = [];
	const segments: CountUpSegment[] = [];
	let finalTier: PayoutTier | undefined;

	for (const tier of tiers) {
		const value = effectiveBaseCash * tier.threshold;
		if (value <= effectiveBaseCash) {
			// Seuil déjà atteint au départ (le premier palier vaut ×1) : c'est le coup
			// d'envoi, il part avec le début du count-up.
			immediate.push(tier);
		} else if (value >= totalEarn) {
			// Le palier tombe pile sur le total : c'est l'arrivée finale qui le joue.
			finalTier = tier;
		} else {
			segments.push({ value, tier });
		}
	}

	segments.push({ value: totalEarn, tier: finalTier });
	return { immediate, segments };
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

// ── Cancellation: payout flushed because another popup opened ───────────────────
//
// Opening any popup while this animation runs drops the finish screen entirely
// (EndGameButtonModule.flush). The animation must stop where it is and hand back what
// has NOT reached the HUD yet, so the caller can show it as one floating text.
//
// Distinct from FloatingCash's rebirth cancellation, which drops the money for good
// instead of paying out the remainder.

interface ActiveRun {
	refs: EndGameRefs;
	totalEarn: number;
	banked: number; // amount whose chunks already landed in the HUD
	cancelled: boolean;
}

let activeRun: ActiveRun | undefined;

// Chunk frames live on the ScreenGui, not on the popup frame — hiding the popup does
// not hide them, so a cancel has to destroy them explicitly.
const FLY_FRAME_NAMES = ["EndGameFloatingChunk", "EndGameBaseCashFly"];

// Puts the popup labels back to their Studio baseline so the next run starts clean.
function resetLabels(refs: EndGameRefs): void {
	refs.baseCashText.Visible = false;
	resetPunchScale(refs.baseCashText);
	if (initialBaseCashSize !== undefined) refs.baseCashText.TextSize = initialBaseCashSize;
	if (initialBaseCashColor !== undefined) refs.baseCashText.TextColor3 = initialBaseCashColor;

	refs.multiplierText.Visible = false;
	if (initialMultiplierPosition !== undefined) refs.multiplierText.Position = initialMultiplierPosition;
	if (initialMultiplierTransparency !== undefined) {
		refs.multiplierText.TextTransparency = initialMultiplierTransparency;
	}
}

// Les particules de l'escalade vivent sur le ScreenGui, pas sur la popup, et la pluie
// tient jusqu'à 9 s alors que le paiement dure ~4 s : sans nettoyage explicite elle
// déborderait sur l'écran suivant.
function clearTierParticles(): void {
	MoneyBurst.clear();
	CriticalRain.clear();
}

// Stops a running payout animation and returns what has not been banked yet.
// Returns undefined when no animation is running (the popup never opened) — the caller
// then falls back to the full amount the server sent.
export function cancelActiveRun(): number | undefined {
	const run = activeRun;
	if (!run || run.cancelled) return undefined;

	run.cancelled = true;
	activeRun = undefined;

	for (const desc of run.refs.screenGui.GetDescendants()) {
		if (FLY_FRAME_NAMES.includes(desc.Name)) desc.Destroy();
	}
	resetLabels(run.refs);
	clearTierParticles();
	InformationText.hide(); // kill a still-showing "Finish" flash

	return math.max(run.totalEarn - run.banked, 0);
}

// Runs the full ButtonFinishGame animation, then calls onComplete().
// Safe to call from a regular task (uses task.wait internally).
export function runEndGameAnimation(
	frame: Frame,
	baseCash: number,
	multiplier: number,
	lossMultiplier: number,
	claimBonus: number,
	onComplete: () => void,
): void {
	const refs = resolveRefs(frame);
	if (!refs) {
		onComplete();
		return;
	}
	const { multiplierText, baseCashText, screenGui } = refs;

	// Snapshot the cancellation generation: a rebirth mid-payout bumps it, and every
	// deferred callback below bails so no chunk lands in the HUD after the reset to 0.
	const runGen = FloatingCash.current();

	if (initialBaseCashSize === undefined) initialBaseCashSize = baseCashText.TextSize;
	if (initialBaseCashColor === undefined) initialBaseCashColor = baseCashText.TextColor3;
	if (initialMultiplierPosition === undefined) initialMultiplierPosition = multiplierText.Position;
	if (initialMultiplierTransparency === undefined) initialMultiplierTransparency = multiplierText.TextTransparency;
	const baseSize = initialBaseCashSize;
	const baseColor = initialBaseCashColor;

	// Le bonus de claim (Perfect ×3 / Critical ×10) grossit la BASE, pas le multiplicateur :
	// tout ce qui suit part donc de la base boostée — le total payé est identique à
	// `claimedBaseCash × multiplier` côté serveur.
	const bonus = claimBonus > 1 ? claimBonus : 1;
	const boostedBaseCash = baseCash * bonus;

	// Kill penalty applies before the multiplier, so the final payout is known up front —
	// register it now so a cancel during the very first phases still knows what is owed.
	const effectiveBaseCash = lossMultiplier < 1 ? boostedBaseCash * lossMultiplier : boostedBaseCash;
	const effectiveBaseSize = lossMultiplier < 1 ? baseSize * lossMultiplier : baseSize;
	const totalEarn = effectiveBaseCash * multiplier;

	const run: ActiveRun = { refs, totalEarn, banked: 0, cancelled: false };
	activeRun = run;

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
	// hold explicite : ce flash SÉQUENCE la suite de l'animation, il garde donc sa
	// durée courte historique au lieu des ~5 s confortables des autres bandeaux.
	InformationText.show(FINISH_TEXT, { holdSeconds: InformationText.HOLD_TIME });
	task.wait(InformationText.FADE_IN_TIME + InformationText.HOLD_TIME);
	if (run.cancelled) return;

	// ── Phase 0: claim bonus — c'est la BASE qui grimpe (×3 Perfect / ×10 Critical) ──
	// Le multiplicateur affiché ne bouge pas : le bonus se lit ici, sur le base cash qui
	// compte de sa valeur brute à sa valeur boostée, en doré et gonflé.
	if (bonus > 1) {
		// Bandeau explicite : sans lui, un joueur pourrait croire que c'est le
		// multiplicateur qui a bougé. Hold court — il ne doit pas traîner sur le paiement.
		InformationText.show(`BASE CASH ×${bonus}`, { rarity: "Epic", holdSeconds: CLAIM_BONUS_BANNER_HOLD });
		animateCash(
			baseCashText,
			baseCash,
			boostedBaseCash,
			baseSize,
			baseSize + CLAIM_BONUS_SIZE_INCREASE,
			baseColor,
			CLAIM_BONUS_COLOR,
			CLAIM_BONUS_TI,
		);
		if (run.cancelled) return;
		task.wait(CLAIM_BONUS_HOLD);
		if (run.cancelled) return;
		// Retour à la taille/couleur de base : la phase multiplicateur repart de zéro.
		animateCash(
			baseCashText,
			boostedBaseCash,
			boostedBaseCash,
			baseSize + CLAIM_BONUS_SIZE_INCREASE,
			baseSize,
			CLAIM_BONUS_COLOR,
			baseColor,
			CLAIM_BONUS_SETTLE_TI,
		);
		if (run.cancelled) return;
	}

	// ── Kill penalty: shrink BaseCashText value + size before the count-up ────────
	if (lossMultiplier < 1) {
		animateCash(
			baseCashText,
			boostedBaseCash,
			effectiveBaseCash,
			baseSize,
			effectiveBaseSize,
			baseColor,
			baseColor,
			LOSS_PENALTY_TI,
		);
		if (run.cancelled) return;
	}

	// ── Phase 1: MultiplierText merges into BaseCashText and disappears ───────────
	mergeMultiplierIntoBaseCash(multiplierText, baseCashText);
	if (run.cancelled) return;

	// ── Phase 2: count-up par paliers ─────────────────────────────────────────────
	// EffectiveBaseCash already includes every money multiplier (rebirth + tier +
	// community), so the start number shows the boost — no separate rebirth phase.
	const grownSize = effectiveBaseSize + BASE_CASH_MAX_SIZE_INCREASE;

	const rocketSpeed = playerStat("RocketSpeed", 1);
	const resistance = playerStat("Resistance", 0);
	const tiers = tiersCrossed(multiplier, rocketSpeed, resistance);
	const { immediate, segments } = buildSegments(effectiveBaseCash, totalEarn, tiers);

	const countUpTime = math.min(
		COUNTUP_BASE_TIME + COUNTUP_TIME_PER_TIER * tiers.size(),
		COUNTUP_MAX_TIME,
	);
	const segmentTime = countUpTime / segments.size();
	const valueTi = new TweenInfo(segmentTime, COUNTUP_VALUE_STYLE, Enum.EasingDirection.Out);
	const styleTi = new TweenInfo(segmentTime, COUNTUP_STYLE_STYLE, Enum.EasingDirection.Out);

	// La taille suit la VALEUR affichée (et non l'index du segment) : le texte grossit
	// donc au même rythme que le nombre, comme avant le découpage.
	const valueSpan = totalEarn - effectiveBaseCash;
	const sizeAt = (value: number) =>
		valueSpan > 0
			? effectiveBaseSize + (grownSize - effectiveBaseSize) * ((value - effectiveBaseCash) / valueSpan)
			: grownSize;

	// Coup d'envoi : les paliers déjà atteints à la valeur de départ claquent tout de
	// suite, sinon le count-up démarrerait en silence.
	let currentColor = baseColor;
	for (const tier of immediate) {
		fireTier(tier, baseCashText);
		currentColor = tier.color;
	}
	baseCashText.TextColor3 = currentColor;

	let currentValue = effectiveBaseCash;
	let currentSize = effectiveBaseSize;
	for (const segment of segments) {
		if (run.cancelled) return;
		const nextSize = sizeAt(segment.value);
		const nextColor = segment.tier?.color ?? currentColor;
		animateCash(
			baseCashText,
			currentValue,
			segment.value,
			currentSize,
			nextSize,
			currentColor,
			nextColor,
			valueTi,
			styleTi,
		);
		if (run.cancelled) return;
		currentValue = segment.value;
		currentSize = nextSize;
		currentColor = nextColor;
		if (segment.tier) fireTier(segment.tier, baseCashText);
	}

	// Couleur atteinte au sommet de l'escalade : la phase 3 redescend vers `baseColor`
	// depuis celle-ci, pas depuis une cible fixe.
	const peakColor = currentColor;

	// ── Phase 3: spray N floating texts into the money HUD ────────────────────────
	const moneyParent = InGameUIController.getMoneyParent();
	const topTier = topTierIndex(multiplier, rocketSpeed, resistance);
	const n = math.min(FLOATING_TEXT_COUNT + FLOATING_TEXT_PER_TIER * topTier, FLOATING_TEXT_MAX);
	const chunk = n > 0 ? totalEarn / n : 0;

	const finishReset = () => {
		// Leave BaseCashText hidden but reset to the Studio baseline for next run.
		baseCashText.Visible = false;
		resetPunchScale(baseCashText);
		if (initialBaseCashSize !== undefined) baseCashText.TextSize = initialBaseCashSize;
		if (initialBaseCashColor !== undefined) baseCashText.TextColor3 = initialBaseCashColor;
	};

	// The run stays "active" (and therefore cancellable) until onComplete actually
	// fires — a popup opening during the final pause must still cancel it, otherwise
	// the flush would fall back to the full amount and pay it a second time.
	const complete = () => {
		if (run.cancelled) return;
		if (activeRun === run) activeRun = undefined;
		onComplete();
	};

	// No HUD target / nothing to spray → deposit visually and finish.
	if (!moneyParent || n <= 0 || totalEarn <= 0) {
		if (totalEarn > 0) {
			MoneyDisplay.addVisual(totalEarn);
			run.banked = totalEarn;
		}
		finishReset();
		complete();
		return;
	}

	let arrived = 0;
	for (let i = 1; i <= n; i++) {
		if (run.cancelled) return; // another popup opened — the leftover leaves as one text
		if (FloatingCash.isStale(runGen)) break; // rebirth cancelled the payout — stop spraying
		const isLast = i === n;
		const remaining = isLast ? 0 : totalEarn - i * chunk;
		spawnFloatingChunk(screenGui, chunk, baseCashText, moneyParent, {
			onSpawn: () => {
				if (run.cancelled) return;
				// Floating text leaving drops BaseCashText by one chunk (value + size).
				baseCashText.Text = formatCash(remaining);
				const ratio = totalEarn > 0 ? remaining / totalEarn : 0;
				baseCashText.TextSize = baseSize + (grownSize - baseSize) * ratio;
				baseCashText.TextColor3 = baseColor.Lerp(peakColor, ratio);
				if (isLast) baseCashText.Visible = false;
			},
			onArrived: () => {
				if (run.cancelled) return; // leftover is handled by the floating text instead
				if (FloatingCash.isStale(runGen)) return; // payout cancelled by a rebirth — don't bank
				// Pitch montant sur la rafale : la répétition devient un crescendo.
				const pitch = 1 + (n > 1 ? (arrived / (n - 1)) * CHUNK_PITCH_RISE : 0);
				MoneyDisplay.addVisual(chunk, { pitch });
				run.banked += chunk;
				arrived += 1;
				if (arrived >= n) {
					// Dernier "boum" : une gerbe part du compteur qui vient de tout encaisser.
					const hudCenter = moneyParent.AbsolutePosition.add(moneyParent.AbsoluteSize.div(2));
					MoneyBurst.play(hudCenter, { count: FINAL_BURST_BASE + topTier });
					if (tiers.size() > 0 && tiers[tiers.size() - 1].bigReward) playBigPayout();
					finishReset();
					task.delay(0.2, complete);
				}
			},
		});
		task.wait(FLOATING_TEXT_INTERVAL);
	}

	// Rebirth broke out of the loop: the money is gone for good, so there is nothing
	// left to flush — drop the run instead of leaving it cancellable.
	if (activeRun === run && FloatingCash.isStale(runGen)) {
		activeRun = undefined;
		finishReset();
		clearTierParticles();
	}
}
