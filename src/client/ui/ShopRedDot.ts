import { Players, TweenService } from "@rbxts/services";
import { SCROLL_TOKENS_ATTR } from "shared/QuestConfig";
import { SCROLL_SHOP_ITEMS, ScrollShopItem, ScrollShopItemId } from "shared/ScrollShopConfig";
import { STATS, ShopStat, isAtCap } from "shared/ShopConfig";

// Pastille rouge « quelque chose est achetable dans la boutique ScrollToken »
// (RedDotNotificationImage), affichée à deux endroits qui partagent le MÊME état :
//   • HUD/ButtonsFrame/QuestsFrame        → mène au panneau des quêtes
//   • QuestsPanel/ButtonsFrame/ShopFrame  → mène à l'onglet boutique
//
// Règle d'affichage — la pastille est allumée tant qu'il reste un objet achetable
// que le joueur n'a PAS encore vu. « Vu » veut dire : il a ouvert l'onglet boutique
// pendant que cet objet était achetable (`acknowledge()`). Ouvrir la boutique éteint
// donc la pastille même sans achat, et elle ne se rallume que quand un objet
// DE PLUS devient achetable (typiquement parce que le solde de tokens a monté).
//
// L'accusé de réception est un état CLIENT, en mémoire, volontairement non persisté :
// à la reconnexion la pastille repart de zéro, ce qui est le bon défaut pour une
// relance (et évite un champ sauvegardé + un RemoteEvent pour un simple point rouge).
//
// « Achetable » reprend exactement les règles que le serveur appliquerait
// (ScrollShopService) : solde suffisant, objet à achat unique pas déjà acquis,
// stat pas au plafond. Sans ça la pastille pourrait pointer un achat refusé.

const player = Players.LocalPlayer;

const DOT_NAME = "RedDotNotificationImage";

// La pastille RESTE affichée ; seule la petite pulsation se rejoue, assez rarement
// pour rappeler sans harceler.
const PULSE_INTERVAL = 40;

// Pulsation : une respiration lente + un balancement, pas une claque.
const PULSE_SCALE = 1.3;
const PULSE_TILT = 12;
const GROW = new TweenInfo(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const SWING = new TweenInfo(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut);
const SETTLE = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

interface Dot {
	readonly image: GuiObject;
	readonly scale: UIScale;
	readonly baseRotation: number;
}

const dots: Dot[] = [];

// Objets achetables que le joueur a déjà vus. Sous-ensemble de l'ensemble achetable
// courant : dès qu'un objet cesse d'être achetable il en sort, pour que le
// redevenir (re-gagner des tokens après un achat) rallume bien la pastille.
const acknowledged = new Set<ScrollShopItemId>();

let shown = false;

function tokens(): number {
	return (player.GetAttribute(SCROLL_TOKENS_ATTR) as number | undefined) ?? 0;
}

function attribute(name: string): number {
	return (player.GetAttribute(name) as number | undefined) ?? 0;
}

// Les trois « +1 niveau de stat » de la boutique portent le nom de leur stat.
function statFor(id: ScrollShopItemId): ShopStat | undefined {
	if (id === "BaseCash" || id === "RocketSpeed" || id === "Resistance") return id;
	return undefined;
}

function isBuyable(item: ScrollShopItem, balance: number): boolean {
	if (balance < item.price) return false;
	if (item.ownedAttribute !== undefined && attribute(item.ownedAttribute) > 0) return false;

	const stat = statFor(item.id);
	if (stat !== undefined && isAtCap(stat, attribute(STATS[stat].levelAttribute))) return false;

	return true;
}

function animate(dot: Dot): void {
	dot.scale.Scale = 1;
	dot.image.Rotation = dot.baseRotation;

	TweenService.Create(dot.scale, GROW, { Scale: PULSE_SCALE }).Play();
	TweenService.Create(dot.image, GROW, { Rotation: dot.baseRotation - PULSE_TILT }).Play();
	task.wait(GROW.Time);

	TweenService.Create(dot.image, SWING, { Rotation: dot.baseRotation + PULSE_TILT }).Play();
	task.wait(SWING.Time);

	TweenService.Create(dot.image, SWING, { Rotation: dot.baseRotation }).Play();
	TweenService.Create(dot.scale, SETTLE, { Scale: 1 }).Play();
}

function pulse(): void {
	for (const dot of dots) {
		if (dot.image.Visible) task.spawn(() => animate(dot));
	}
}

function setShown(value: boolean): void {
	if (shown === value) return;
	shown = value;

	for (const dot of dots) {
		dot.image.Visible = value;
		if (!value) {
			dot.scale.Scale = 1;
			dot.image.Rotation = dot.baseRotation;
		}
	}

	// Apparition : on pulse tout de suite, sinon le joueur peut attendre 40s avant le
	// premier signe de vie.
	if (value) pulse();
}

function refresh(): void {
	const balance = tokens();
	let hasUnseen = false;

	for (const item of SCROLL_SHOP_ITEMS) {
		if (isBuyable(item, balance)) {
			if (!acknowledged.has(item.id)) hasUnseen = true;
		} else {
			acknowledged.delete(item.id);
		}
	}

	setShown(hasUnseen);
}

// Résout une pastille. FindFirstChild partout : une pastille absente ou renommée ne
// doit coûter que cet affichage, jamais le blocage des init clients suivants.
function readDot(parent: Instance): void {
	const image = parent.FindFirstChild(DOT_NAME);
	if (!image?.IsA("GuiObject")) {
		warn(`ShopRedDot: ${DOT_NAME} introuvable sous ${parent.GetFullName()}`);
		return;
	}

	const existing = image.FindFirstChildOfClass("UIScale");
	let scale: UIScale;
	if (existing) {
		scale = existing;
	} else {
		scale = new Instance("UIScale");
		scale.Parent = image;
	}
	scale.Scale = 1;

	image.Visible = false; // l'état vient du code, pas du défaut posé en Studio
	dots.push({ image, scale, baseRotation: image.Rotation });
}

export const ShopRedDot = {
	init(): void {
		const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");

		const hudButtons = (inGameUI.WaitForChild("HUD") as GuiObject).WaitForChild("ButtonsFrame");
		readDot(hudButtons.WaitForChild("QuestsFrame"));

		const panelTabs = (inGameUI.WaitForChild("QuestsPanel") as GuiObject).WaitForChild("ButtonsFrame");
		readDot(panelTabs.WaitForChild("ShopFrame"));

		player.GetAttributeChangedSignal(SCROLL_TOKENS_ATTR).Connect(refresh);
		for (const item of SCROLL_SHOP_ITEMS) {
			if (item.ownedAttribute !== undefined) {
				player.GetAttributeChangedSignal(item.ownedAttribute).Connect(refresh);
			}
		}
		for (const stat of ["BaseCash", "RocketSpeed", "Resistance"] as ShopStat[]) {
			player.GetAttributeChangedSignal(STATS[stat].levelAttribute).Connect(refresh);
		}

		refresh();

		task.spawn(() => {
			for (;;) {
				task.wait(PULSE_INTERVAL);
				if (shown) pulse();
			}
		});
	},

	// À appeler quand le joueur affiche l'onglet boutique : tout ce qui est achetable
	// à cet instant est considéré comme vu, la pastille s'éteint jusqu'à ce qu'un
	// objet de PLUS devienne achetable.
	acknowledge(): void {
		const balance = tokens();
		acknowledged.clear();
		for (const item of SCROLL_SHOP_ITEMS) {
			if (isBuyable(item, balance)) acknowledged.add(item.id);
		}
		refresh();
	},
};
