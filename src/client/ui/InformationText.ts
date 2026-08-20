import { Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";
import { Events } from "shared/Event";
import type { InformationRarity, InformationTextOptions } from "shared/InformationRarity";

// Bandeaux d'information du HUD, empilables.
//
// InGameUI/InformationTextCanvasGroup est un simple CONTENEUR (UIListLayout
// vertical) : chaque message clone le template `InformationEntry` et s'ajoute
// SOUS le précédent, avec son propre fondu. Plusieurs messages peuvent donc
// vivre en même temps.
//
//   InformationText.show("Finish");
//   InformationText.show("Pas assez d'argent", { color: DENIED_COLOR });
//   InformationText.show("Nouveau record !", { rarity: "Epic" });
//
// Chaque rareté a sa hauteur (le texte est TextScaled → la hauteur pilote la
// taille), son gradient et son son. Legendary utilise un TextLabel dédié
// (LegendaryText) qui embarque le script RainbowText.

const FADE_IN_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const FADE_OUT_TI = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// Durée d'affichage historique du flash "Finish" de fin de partie : elle SÉQUENCE
// l'animation de paiement (EndGameAnimation attend FADE_IN + ce hold avant de
// lancer la descente du multiplicateur), donc elle ne suit PAS les durées
// confortables des bandeaux ci-dessous — l'appelant la passe explicitement.
const FINISH_HOLD = 0.2;

const DEFAULT_COLOR = new Color3(1, 1, 1);
const CANVAS_NAME = "InformationTextCanvasGroup";
const TEMPLATE_NAME = "InformationEntry";
const LABEL_NAME = "InformationText";
const LEGENDARY_LABEL_NAME = "LegendaryText";
const RAINBOW_SCRIPT_NAME = "RainbowText";

// Au-delà, le plus ancien bandeau est retiré instantanément : l'écran ne se
// remplit jamais de messages.
const MAX_ENTRIES = 5;

// ── Descente pendant un vol ───────────────────────────────────────────────────
// Position Y (fraction d'écran) du HAUT de la pile pendant un vol. Le HUD de vol
// pose son gros MultiplierText en haut-centre (0.08 → 0.21 de l'écran), pile là
// où les bandeaux s'empilent : ils descendent donc sous lui le temps du vol, puis
// remontent à leur position Studio. `setInFlight` est piloté par
// RocketLaunchBehavior (décollage / fin de partie).
const IN_FLIGHT_Y = 0.24;
const MOVE_TI = new TweenInfo(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

interface RarityStyle {
	// Hauteur du bandeau en fraction de la HAUTEUR D'ÉCRAN (texte TextScaled,
	// donc c'est aussi ce qui donne la taille du texte).
	height: number;
	// Nom du UIGradient à activer sur le TextLabel (posés en Studio).
	// `undefined` = aucun gradient. Un "CommonGradient" existe en Studio mais
	// reste éteint : le renseigner ici suffit à l'allumer.
	gradient?: string;
	// Utilise le TextLabel dédié LegendaryText au lieu de InformationText.
	legendary?: boolean;
	// Temps à pleine opacité, hors fondus (+0.7 s au total). Surchargeable par
	// `holdSeconds` à l'appel.
	hold: number;
	// `undefined` = silencieux. Common l'est : c'est le bandeau le plus fréquent
	// (refus d'achat, hints…), un son à chaque fois devient vite pénible.
	sound?: { id: string; volume: number };
}

const STYLES: Record<InformationRarity, RarityStyle> = {
	Common: { height: 0.08, hold: 5 },
	Rare: { height: 0.09, hold: 5, gradient: "RareGradient", sound: AudioConfig.sfx.information },
	Epic: { height: 0.1, hold: 5, gradient: "EpicGradient", sound: AudioConfig.sfx.information },
	Legendary: { height: 0.12, hold: 6.5, legendary: true, sound: AudioConfig.sfx.informationLegendary },
};

const GRADIENT_NAMES = ["CommonGradient", "RareGradient", "EpicGradient"];

// ── Sons ──────────────────────────────────────────────────────────────────────
// Templates persistants en SoundService (même approche que UiClickSound) :
// l'asset reste en mémoire et les clones peuvent se chevaucher.
const soundTemplates = new Map<string, Sound>();

function playSound(def: { id: string; volume: number }): void {
	let template = soundTemplates.get(def.id);
	if (!template) {
		template = new Instance("Sound");
		template.Name = "InformationTextTemplate";
		template.SoundId = def.id;
		template.Volume = def.volume;
		template.Parent = SoundService;
		soundTemplates.set(def.id, template);
	}
	const sound = template.Clone();
	sound.Parent = SoundService;
	sound.Play();
	sound.Ended.Connect(() => sound.Destroy());
}

// ── Références GUI ────────────────────────────────────────────────────────────
let cachedCanvas: CanvasGroup | undefined;
// Position authored en Studio, capturée au premier appel de setInFlight (donc
// avant tout déplacement) : c'est celle qu'on restaure en fin de vol.
let authoredPosition: UDim2 | undefined;
let moveTween: Tween | undefined;

function findCanvas(): CanvasGroup | undefined {
	if (cachedCanvas && cachedCanvas.Parent !== undefined) return cachedCanvas;
	const gui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	if (!gui) return undefined;
	for (const desc of gui.GetDescendants()) {
		if (desc.Name === CANVAS_NAME && desc.IsA("CanvasGroup")) {
			cachedCanvas = desc;
			return desc;
		}
	}
	return undefined;
}

function findTemplate(canvas: CanvasGroup): CanvasGroup | undefined {
	const found = canvas.FindFirstChild(TEMPLATE_NAME);
	return found !== undefined && found.IsA("CanvasGroup") ? found : undefined;
}

function findLabel(entry: CanvasGroup, name: string): TextLabel | undefined {
	const found = entry.FindFirstChild(name, true);
	return found !== undefined && found.IsA("TextLabel") ? found : undefined;
}

// Les hauteurs de STYLES sont en fraction d'écran, mais une entrée est
// dimensionnée par rapport au conteneur (qui n'occupe qu'une tranche de
// l'écran) : on convertit à la volée pour rester juste même si le conteneur est
// redimensionné en Studio.
function entryHeightScale(canvas: CanvasGroup, screenFraction: number): number {
	const containerScale = canvas.Size.Y.Scale;
	if (containerScale <= 0) return screenFraction;
	return screenFraction / containerScale;
}

// ── Pile active ───────────────────────────────────────────────────────────────
interface ActiveEntry {
	instance: CanvasGroup;
	tweens: Tween[];
	// Passe à -1 quand l'entrée est retirée : invalide les task.delay en vol.
	token: number;
}

const active: ActiveEntry[] = [];
let nextLayoutOrder = 0;
let nextToken = 0;

function removeEntry(entry: ActiveEntry): void {
	if (entry.token === -1) return;
	entry.token = -1;
	for (const t of entry.tweens) t.Cancel();
	const index = active.indexOf(entry);
	if (index >= 0) active.remove(index);
	entry.instance.Destroy();
}

export const InformationText = {
	// Exposé pour les appelants qui séquencent d'autres animations autour du
	// bandeau (EndGameAnimation attend FADE_IN_TIME + HOLD_TIME avant de lancer
	// la descente du multiplicateur — et repasse HOLD_TIME en `holdSeconds`,
	// sinon le "Finish" traînerait 5 s par-dessus l'écran de paiement).
	FADE_IN_TIME: FADE_IN_TI.Time,
	HOLD_TIME: FINISH_HOLD,
	FADE_OUT_TIME: FADE_OUT_TI.Time,

	// Pendant un vol, la pile descend pour ne pas recouvrir le MultiplierText du HUD
	// de vol ; en fin de vol elle remonte à sa position Studio. Appelé par
	// RocketLaunchBehavior au décollage et sur GameResultEvent (toutes les fins de
	// partie passent par là : explosion post-claim, perte, "Go Home").
	setInFlight(inFlight: boolean): void {
		const canvas = findCanvas();
		if (!canvas) return;
		if (authoredPosition === undefined) authoredPosition = canvas.Position;

		const target = inFlight
			? new UDim2(authoredPosition.X.Scale, authoredPosition.X.Offset, IN_FLIGHT_Y, 0)
			: authoredPosition;
		if (moveTween) moveTween.Cancel();
		moveTween = TweenService.Create(canvas, MOVE_TI, { Position: target });
		moveTween.Play();
	},

	// Vide la pile instantanément, en pleine animation. Utilisé quand le paiement
	// de fin de partie est annulé par un autre popup : le "Finish" ne doit pas
	// traîner par-dessus le nouvel écran.
	hide(): void {
		for (const entry of [...active]) removeEntry(entry);
	},

	show(text: string, options?: InformationTextOptions): void {
		const canvas = findCanvas();
		if (!canvas) {
			warn(`InformationText: ${CANVAS_NAME} introuvable sous PlayerGui`);
			return;
		}
		const template = findTemplate(canvas);
		if (!template) {
			warn(`InformationText: template ${TEMPLATE_NAME} introuvable sous ${CANVAS_NAME}`);
			return;
		}

		const rarity = options?.rarity ?? "Common";
		const style = STYLES[rarity];
		const isLegendary = style.legendary === true;

		while (active.size() >= MAX_ENTRIES) removeEntry(active[0]);

		const instance = template.Clone();
		instance.Name = `${TEMPLATE_NAME}_${rarity}`;
		instance.Size = UDim2.fromScale(1, entryHeightScale(canvas, style.height));
		instance.GroupTransparency = 1;
		// Ordre croissant : le nouveau bandeau se place SOUS le plus récent.
		instance.LayoutOrder = nextLayoutOrder;
		nextLayoutOrder += 1;

		const normalLabel = findLabel(instance, LABEL_NAME);
		const legendaryLabel = findLabel(instance, LEGENDARY_LABEL_NAME);
		if (normalLabel) normalLabel.Visible = !isLegendary;
		if (legendaryLabel) {
			legendaryLabel.Visible = isLegendary;
			// Le script arc-en-ciel est désactivé dans le template : il ne tourne
			// que sur les bandeaux Legendary (une boucle par bandeau affiché).
			const rainbow = legendaryLabel.FindFirstChild(RAINBOW_SCRIPT_NAME);
			if (rainbow !== undefined && rainbow.IsA("LocalScript")) rainbow.Enabled = isLegendary;
		}

		const label = isLegendary ? legendaryLabel : normalLabel;
		if (label) {
			label.Text = text;
			// En Legendary la couleur est pilotée par le script RainbowText.
			if (!isLegendary) label.TextColor3 = options?.color ?? DEFAULT_COLOR;
			for (const name of GRADIENT_NAMES) {
				const gradient = label.FindFirstChild(name);
				if (gradient !== undefined && gradient.IsA("UIGradient")) gradient.Enabled = name === style.gradient;
			}
		}

		instance.Visible = true;
		instance.Parent = canvas;

		nextToken += 1;
		const entry: ActiveEntry = { instance, tweens: [], token: nextToken };
		const myToken = entry.token;
		active.push(entry);

		if (style.sound) playSound(style.sound);

		const fadeIn = TweenService.Create(instance, FADE_IN_TI, { GroupTransparency: 0 });
		entry.tweens.push(fadeIn);
		fadeIn.Play();

		const hold = options?.holdSeconds ?? style.hold;
		task.delay(FADE_IN_TI.Time + hold, () => {
			if (entry.token !== myToken) return; // entrée déjà retirée
			const fadeOut = TweenService.Create(instance, FADE_OUT_TI, { GroupTransparency: 1 });
			entry.tweens.push(fadeOut);
			fadeOut.Completed.Connect(() => removeEntry(entry));
			fadeOut.Play();
		});
	},
};

export function init(): void {
	Events.InformationTextEvent.OnClientEvent.Connect((text: string, options?: InformationTextOptions) => {
		InformationText.show(text, options);
	});
}
