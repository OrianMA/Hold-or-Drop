import { RunService } from "@rbxts/services";

// Cascade d'ouverture d'un body du panneau des quêtes (QuestsBody / BuyRewardBody).
// Rejouée à CHAQUE affichage — ouverture du panneau comme changement d'onglet — pour
// que le passage d'un body à l'autre soit un vrai changement d'écran et pas une
// substitution silencieuse.
//
// Les éléments apparaissent l'un après l'autre en FONDU. Le fondu et pas un
// glissement ou un pop d'échelle : les deux bodies sont pilotés par un layout
// (UIListLayout / UIGridLayout) qui possède la position ET la taille de ses enfants,
// donc toute animation de géométrie ferait re-couler la liste à chaque frame. La
// transparence, elle, n'a aucun effet sur le layout.
//
// Même discipline que DailyRewardsAnimation : les valeurs d'origine sont CAPTURÉES
// au premier passage puis restaurées — rien n'est réécrit "en dur", donc retoucher
// les transparences en Studio reste sans risque. Un compteur de génération invalide
// une cascade abandonnée (changement d'onglet en plein fondu).

// Durée du fondu d'UN élément, et décalage entre deux éléments consécutifs.
const FADE_DURATION = 0.22;
const STAGGER = 0.035;

// Propriété de transparence capturée par instance, avec sa valeur d'origine.
interface Fade {
	instance: Instance;
	property: string;
	original: number;
}

interface Element {
	fades: Fade[];
	delay: number;
}

// Un état par body : la capture est faite une fois pour toutes.
const captured = new Map<GuiObject, Element[]>();
const running = new Map<GuiObject, RBXScriptConnection>();

function fadeProperties(instance: Instance, into: Fade[]): void {
	if (instance.IsA("GuiObject")) {
		into.push({ instance, property: "BackgroundTransparency", original: instance.BackgroundTransparency });
	}
	if (instance.IsA("TextLabel") || instance.IsA("TextButton")) {
		into.push({ instance, property: "TextTransparency", original: instance.TextTransparency });
	}
	if (instance.IsA("ImageLabel") || instance.IsA("ImageButton")) {
		into.push({ instance, property: "ImageTransparency", original: instance.ImageTransparency });
	}
	if (instance.IsA("UIStroke")) {
		into.push({ instance, property: "Transparency", original: instance.Transparency });
	}
}

// Les deux layouts trient par NOM (SortOrder.Name), donc l'ordre alphabétique EST
// l'ordre visuel — inutile de lire des positions absolues, qui ne seraient de toute
// façon pas encore calculées au moment où le body s'affiche.
function elementsOf(body: GuiObject): Element[] {
	const found = captured.get(body);
	if (found) return found;

	const scrollingFrame = body.FindFirstChild("ScrollingFrame");
	const elements: Element[] = [];
	if (!scrollingFrame) {
		captured.set(body, elements);
		return elements;
	}

	const children: GuiObject[] = [];
	for (const child of scrollingFrame.GetChildren()) {
		if (child.IsA("GuiObject")) children.push(child);
	}
	children.sort((a, b) => a.Name < b.Name);

	for (let i = 0; i < children.size(); i++) {
		const fades: Fade[] = [];
		fadeProperties(children[i], fades);
		for (const descendant of children[i].GetDescendants()) fadeProperties(descendant, fades);
		elements.push({ fades, delay: i * STAGGER });
	}

	captured.set(body, elements);
	return elements;
}

// alpha 0 = invisible, 1 = valeur d'origine.
function applyAlpha(element: Element, alpha: number): void {
	for (const fade of element.fades) {
		// L'opacité d'origine est le PLANCHER : un élément déjà à 0.5 ne devient jamais
		// plus opaque que 0.5.
		const value = fade.original + (1 - fade.original) * (1 - alpha);
		(fade.instance as unknown as Record<string, number>)[fade.property] = value;
	}
}

function stopLoop(body: GuiObject): void {
	const connection = running.get(body);
	if (connection) {
		connection.Disconnect();
		running.delete(body);
	}
}

export const QuestsBodyAnimation = {
	// Joue la cascade. Rejouable à volonté : une cascade en cours est abandonnée et
	// remplacée, jamais superposée.
	play(body: GuiObject): void {
		const elements = elementsOf(body);
		if (elements.isEmpty()) return;

		stopLoop(body);
		for (const element of elements) applyAlpha(element, 0);

		const last = elements[elements.size() - 1];
		const total = last.delay + FADE_DURATION;
		let elapsed = 0;

		const connection = RunService.RenderStepped.Connect((delta) => {
			elapsed += delta;
			for (const element of elements) {
				const raw = math.clamp((elapsed - element.delay) / FADE_DURATION, 0, 1);
				// Ease-out : l'élément prend sa pleine opacité vite puis se stabilise.
				applyAlpha(element, 1 - (1 - raw) * (1 - raw));
			}
			if (elapsed >= total) {
				stopLoop(body);
				for (const element of elements) applyAlpha(element, 1);
			}
		});
		running.set(body, connection);
	},

	// Coupe une cascade en cours et remet tout à l'opacité d'origine — appelé quand le
	// body est masqué, sinon il resterait figé à demi transparent.
	stop(body: GuiObject): void {
		stopLoop(body);
		const elements = captured.get(body);
		if (!elements) return;
		for (const element of elements) applyAlpha(element, 1);
	},
};
