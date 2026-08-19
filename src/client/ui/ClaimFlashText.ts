import { Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";
import { CRITICAL_CLAIM_MULTIPLIER, PERFECT_CLAIM_MULTIPLIER } from "shared/RocketGameConfig";

// ── Flashs de claim bonus ──────────────────────────────────────────────────────
//
// Deux textes plein écran, même animation et même son :
//   • "PERFECT CLAIM  BASE CASH ×3"  — rouge  — claim juste avant l'explosion, joué À
//     L'EXPLOSION (c'est le boom qui valide le coup).
//   • "CRITICAL CLAIM  BASE CASH ×10" — doré et brillant (dégradé balayé par un reflet)
//     — 5 % de chance à chaque claim, joué AU CLAIM.
//
// Les deux bonus multiplient le BASE CASH, jamais le multiplicateur : le texte le dit
// explicitement, et la popup de fin montre la base grimper (client/ui/EndGameAnimation).
//
// Les deux peuvent tomber sur le même run : comme les bandeaux InformationText, chaque
// flash prend sa propre ligne (slot) et vit sa vie indépendamment — plusieurs textes
// peuvent donc être affichés en même temps, jamais l'un sur l'autre.
//
// Rien à préparer en Studio : les labels sont créés en code sous InGameUI, donc ils
// suivent automatiquement le viewport (TextScaled + tailles en scale ⇒ lisible mobile).

const LABEL_NAME = "ClaimFlashText";

const SIZE = UDim2.fromScale(0.72, 0.13);
const BASE_Y = 0.43; // milieu de l'écran, un poil au-dessus de la ligne centrale
const SLOT_SPACING = 0.15; // hauteur d'une ligne : les flashs suivants s'empilent en dessous
const MAX_FLASHES = 3; // au-delà, le plus ancien est retiré net (l'écran ne se remplit pas)
const Z_INDEX = 60; // par-dessus le HUD et la gerbe de billets
const STROKE_THICKNESS = 4;

// Arrivée : le texte débarque énorme et de travers, puis claque à sa taille.
const START_SCALE = 2.4;
const START_ROTATION = -7;
const SLAM_TI = new TweenInfo(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const APPEAR_TI = new TweenInfo(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

const HOLD = 2; // s à pleine opacité — le flash doit rester lisible
const OUT_SCALE = 1.3;
const OUT_TI = new TweenInfo(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// Reflet du critical : le dégradé doré est balayé de gauche à droite en boucle. Hors du
// balayage le texte reste doré (les deux bouts du dégradé sont de l'or foncé).
const SHINE_TI = new TweenInfo(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1);
const GOLD_GRADIENT = new ColorSequence([
	new ColorSequenceKeypoint(0, Color3.fromRGB(255, 170, 32)),
	new ColorSequenceKeypoint(0.42, Color3.fromRGB(255, 214, 92)),
	new ColorSequenceKeypoint(0.5, Color3.fromRGB(255, 255, 235)),
	new ColorSequenceKeypoint(0.58, Color3.fromRGB(255, 214, 92)),
	new ColorSequenceKeypoint(1, Color3.fromRGB(255, 170, 32)),
]);
const SHINE_ROTATION = 20;

interface FlashStyle {
	text: string;
	color: Color3;
	// Dégradé doré + reflet balayant (critical). `false` ⇒ texte plein.
	shine: boolean;
}

const PERFECT_STYLE: FlashStyle = {
	text: `PERFECT CLAIM  BASE CASH ×${PERFECT_CLAIM_MULTIPLIER}`,
	color: Color3.fromRGB(255, 38, 38),
	shine: false,
};

const CRITICAL_STYLE: FlashStyle = {
	text: `CRITICAL CLAIM  BASE CASH ×${CRITICAL_CLAIM_MULTIPLIER}`,
	color: new Color3(1, 1, 1), // blanc : c'est le dégradé doré qui donne la couleur
	shine: true,
};

// ── Son ───────────────────────────────────────────────────────────────────────
// Template persistant en SoundService (même approche que UiClickSound / InformationText) :
// l'asset reste en mémoire, les clones peuvent se chevaucher.
let soundTemplate: Sound | undefined;

function playSound(): void {
	if (!soundTemplate) {
		const template = new Instance("Sound");
		template.Name = "ClaimFlashSoundTemplate";
		template.SoundId = AudioConfig.sfx.perfectClaim.id;
		template.Volume = AudioConfig.sfx.perfectClaim.volume;
		template.Parent = SoundService;
		soundTemplate = template;
	}
	const sound = soundTemplate.Clone();
	sound.Parent = SoundService;
	sound.Play();
	sound.Ended.Connect(() => sound.Destroy());
}

// ── Pile active ───────────────────────────────────────────────────────────────
interface ActiveFlash {
	label: TextLabel;
	stroke: UIStroke;
	scale: UIScale;
	tweens: Tween[];
	slot: number;
	alive: boolean; // passe à false au retrait : invalide les task.delay en vol
}

const active: ActiveFlash[] = [];

function getScreenGui(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

// Plus petite ligne libre : deux flashs simultanés ne se superposent jamais.
function freeSlot(): number {
	for (let slot = 0; slot < MAX_FLASHES; slot++) {
		let taken = false;
		for (const flash of active) if (flash.slot === slot) taken = true;
		if (!taken) return slot;
	}
	return 0;
}

function remove(flash: ActiveFlash): void {
	if (!flash.alive) return;
	flash.alive = false;
	for (const tween of flash.tweens) tween.Cancel();
	flash.tweens.clear();
	flash.label.Destroy();
	const index = active.indexOf(flash);
	if (index >= 0) active.remove(index);
}

function play<T extends Instance>(
	flash: ActiveFlash,
	target: T,
	info: TweenInfo,
	goal: Partial<ExtractMembers<T, Tweenable>>,
): void {
	const tween = TweenService.Create(target, info, goal);
	flash.tweens.push(tween);
	tween.Play();
}

function show(style: FlashStyle): void {
	const screenGui = getScreenGui();
	if (!screenGui) return;

	if (active.size() >= MAX_FLASHES) remove(active[0]);

	const slot = freeSlot();

	const label = new Instance("TextLabel");
	label.Name = LABEL_NAME;
	label.AnchorPoint = new Vector2(0.5, 0.5);
	label.Position = UDim2.fromScale(0.5, BASE_Y + slot * SLOT_SPACING);
	label.Size = SIZE;
	label.BackgroundTransparency = 1;
	label.Text = style.text;
	label.TextScaled = true;
	label.TextColor3 = style.color;
	label.TextTransparency = 1;
	label.FontFace = new Font("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold);
	label.ZIndex = Z_INDEX;

	const stroke = new Instance("UIStroke");
	stroke.Thickness = STROKE_THICKNESS;
	stroke.Color = new Color3(0, 0, 0);
	stroke.Transparency = 1;
	stroke.Parent = label;

	const scale = new Instance("UIScale");
	scale.Scale = START_SCALE;
	scale.Parent = label;

	label.Rotation = START_ROTATION;
	label.Parent = screenGui;

	const flash: ActiveFlash = { label, stroke, scale, tweens: [], slot, alive: true };
	active.push(flash);

	// Critical : dégradé doré + reflet qui traverse le texte en boucle.
	if (style.shine) {
		const gradient = new Instance("UIGradient");
		gradient.Color = GOLD_GRADIENT;
		gradient.Rotation = SHINE_ROTATION;
		gradient.Offset = new Vector2(-1, 0);
		gradient.Parent = label;
		play(flash, gradient, SHINE_TI, { Offset: new Vector2(1, 0) });
	}

	playSound();

	play(flash, scale, SLAM_TI, { Scale: 1 });
	play(flash, label, SLAM_TI, { Rotation: 0 });
	play(flash, label, APPEAR_TI, { TextTransparency: 0 });
	play(flash, stroke, APPEAR_TI, { Transparency: 0 });

	task.delay(SLAM_TI.Time + HOLD, () => {
		if (!flash.alive) return;
		play(flash, scale, OUT_TI, { Scale: OUT_SCALE });
		play(flash, label, OUT_TI, { TextTransparency: 1 });
		play(flash, stroke, OUT_TI, { Transparency: 1 });
		task.delay(OUT_TI.Time, () => remove(flash));
	});
}

export const ClaimFlashText = {
	// Rouge, ×3 — joué à l'explosion qui suit un Perfect Claim.
	showPerfect(): void {
		show(PERFECT_STYLE);
	},

	// Doré brillant, ×10 — joué au claim quand le tirage critique passe.
	showCritical(): void {
		show(CRITICAL_STYLE);
	},

	// Coupe tous les flashs instantanément (fin de partie / rebirth pendant l'animation).
	hide(): void {
		for (let i = active.size() - 1; i >= 0; i--) remove(active[i]);
	},
};
