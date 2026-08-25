import { Players, RunService, TweenService, UserInputService } from "@rbxts/services";

// Animation de survol / clic centralisée pour TOUTE l'UI. Même principe que
// UiClickSound : au lieu de câbler l'anim bouton par bouton, on accroche
// automatiquement chaque GuiButton du PlayerGui — ceux déjà présents au
// démarrage et ceux ajoutés plus tard (DescendantAdded). Tout nouveau bouton
// créé en Studio est animé sans une ligne de code en plus.
//
// 100 % client / présentation.
//
// DEUX choix structurants :
//
// 1. On anime la FRAME PARENTE, pas le bouton. Dans cette UI le GuiButton est
//    presque toujours une zone de clic transparente posée sur une Frame qui
//    porte tout le visuel (UICorner, UIStroke, UIGradient, TextLabel, sous-
//    frames) : ShopMoneyBuy/MoneyElementN/Button, QuestsPanel/…/BuyButtonFrame/
//    TextButton, HUD/ButtonsFrame/QuestsFrame/ImageButton… Scaler le bouton seul
//    ne bougerait rien de visible. Voir resolveTarget() pour la règle exacte et
//    les cas où on reste sur le bouton.
//
// 2. On anime un UIScale, JAMAIS la propriété Size : plusieurs systèmes tweenent
//    déjà Size (le pulse du ClaimButton, la barre de progression) et le layout
//    (UIListLayout/UIGridLayout) est calculé sur Size. Le UIScale est purement
//    visuel, ne décale rien, et ne peut donc entrer en conflit avec personne.
//
// Un bouton marqué avec l'attribut `NoUiAnim` est ignoré (échappatoire pour un
// bouton qui aurait sa propre animation).

const SCALE_NAME = "UiAnimScale";

// ScreenGui généré par Roblox pour les ProximityPrompts par défaut : UI système,
// créée/détruite en continu — on n'y touche pas.
const IGNORED_SCREENGUI = "ProximityPrompts";

// Facteurs appliqués par-dessus l'échelle d'origine de la cible.
const HOVER_SCALE = 1.07; // survol : l'élément avance un peu vers le joueur
const PRESS_SCALE = 0.92; // appui : il s'enfonce

// Survol : entrée avec un léger dépassement (Back), sortie neutre et douce.
const HOVER_IN_TI = new TweenInfo(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const HOVER_OUT_TI = new TweenInfo(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
// Appui : très court, pour que l'enfoncement colle au doigt / au clic.
const PRESS_TI = new TweenInfo(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
// Relâche : le "pop" satisfaisant — rebond au-delà de la cible puis retour.
const RELEASE_TI = new TweenInfo(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out);

// Le bouton doit couvrir au moins cette fraction de sa frame parente pour qu'on
// considère qu'il « est » cette frame (et donc qu'on anime la frame).
const FILL_THRESHOLD = 0.75;

interface ButtonState {
	button: GuiButton; // la cible du clic (sert aussi au test de visibilité)
	scale: UIScale; // posé sur la cible animée (frame parente ou bouton)
	base: number; // échelle d'origine (1 en général) — la cible en est un multiple
	hovered: boolean;
	pressed: boolean;
	tween?: Tween;
}

const states = new Map<GuiButton, ButtonState>();

// Un seul bouton est survolé/pressé à la fois : on ne surveille que celui-là.
let activeState: ButtonState | undefined;
let watchConn: RBXScriptConnection | undefined;

// Quoi faire grossir : la frame parente quand le bouton n'est qu'une hitbox
// posée dessus, sinon le bouton lui-même.
//
// On remonte au parent seulement si les deux conditions tiennent :
//   • le parent ne contient QU'UN seul GuiButton — sinon survoler BuyButton
//     ferait aussi grossir RobuxButton (ShopMenu/…/ButtonsLayout) ;
//   • le bouton remplit son parent — sinon on ferait grossir tout un Header
//     (ShopMenu/Header/CloseButton) ou toute une popup (ButtonMenu/StartButton).
function resolveTarget(button: GuiButton): GuiObject {
	const parent = button.Parent;
	if (parent === undefined || !parent.IsA("GuiObject")) return button;

	const size = button.Size;
	const fills =
		size.X.Scale >= FILL_THRESHOLD && size.Y.Scale >= FILL_THRESHOLD && size.X.Offset <= 0 && size.Y.Offset <= 0;
	if (!fills) return button;

	for (const child of parent.GetChildren()) {
		if (child !== button && child.IsA("GuiButton")) return button; // frère bouton
	}
	return parent;
}

function targetScale(state: ButtonState): number {
	if (state.pressed) return state.base * PRESS_SCALE;
	if (state.hovered) return state.base * HOVER_SCALE;
	return state.base;
}

function animate(state: ButtonState, info: TweenInfo): void {
	state.tween?.Cancel();
	state.tween?.Destroy();
	const tween = TweenService.Create(state.scale, info, { Scale: targetScale(state) });
	state.tween = tween;
	tween.Play();
}

// Retour immédiat au repos, sans tween — pour les cas où l'élément disparaît
// alors qu'il est survolé/pressé (fermeture de popup) et ne recevra jamais son
// MouseLeave : il ne doit pas réapparaître agrandi.
function reset(state: ButtonState): void {
	state.hovered = false;
	state.pressed = false;
	state.tween?.Cancel();
	state.tween?.Destroy();
	state.tween = undefined;
	state.scale.Scale = state.base;
}

// Visibilité *effective* : le bouton lui-même, tous ses ancêtres GuiObject, et
// le ScreenGui qui les porte.
function isShown(button: GuiButton): boolean {
	let node: Instance | undefined = button;
	while (node !== undefined) {
		if (node.IsA("GuiObject") && !node.Visible) return false;
		if (node.IsA("LayerCollector")) return node.Enabled;
		node = node.Parent;
	}
	return false; // détaché du PlayerGui
}

// Roblox ne déclenche PAS MouseLeave quand un ancêtre passe en Visible = false
// (fermeture de popup). Sans ce garde-fou l'élément resterait figé agrandi et
// réapparaîtrait ainsi à la réouverture. Tant qu'un bouton est actif, on vérifie
// chaque frame qu'il est toujours à l'écran — une seule connexion, quelques
// ancêtres à remonter.
function setActive(state: ButtonState | undefined): void {
	activeState = state;
	if (state === undefined) {
		watchConn?.Disconnect();
		watchConn = undefined;
		return;
	}
	if (watchConn !== undefined) return;
	watchConn = RunService.Heartbeat.Connect(() => {
		const current = activeState;
		if (current === undefined) return;
		if (isShown(current.button)) return;
		reset(current);
		setActive(undefined);
	});
}

function hook(instance: Instance): void {
	if (!instance.IsA("GuiButton")) return;
	if (states.has(instance)) return;
	if (instance.GetAttribute("NoUiAnim") === true) return;
	if (instance.FindFirstAncestor(IGNORED_SCREENGUI) !== undefined) return;

	const button = instance;
	const target = resolveTarget(button);
	// Réutilise un UIScale déjà présent (posé en Studio pour le style) plutôt que
	// d'en ajouter un second : Roblox n'en applique qu'un seul par GuiObject.
	let scale = target.FindFirstChildOfClass("UIScale");
	if (!scale) {
		scale = new Instance("UIScale");
		scale.Name = SCALE_NAME;
		scale.Parent = target;
	}

	const state: ButtonState = { button, scale, base: scale.Scale, hovered: false, pressed: false };
	states.set(button, state);

	button.MouseEnter.Connect(() => {
		state.hovered = true;
		setActive(state);
		animate(state, HOVER_IN_TI);
	});
	button.MouseLeave.Connect(() => {
		// Sortir du bouton annule aussi l'appui : relâcher dehors ne doit pas
		// laisser l'élément enfoncé.
		state.hovered = false;
		state.pressed = false;
		if (activeState === state) setActive(undefined);
		animate(state, HOVER_OUT_TI);
	});
	button.MouseButton1Down.Connect(() => {
		state.pressed = true;
		setActive(state);
		animate(state, PRESS_TI);
	});
	button.MouseButton1Up.Connect(() => {
		state.pressed = false;
		animate(state, RELEASE_TI);
	});

	// Navigation manette : le focus se comporte comme un survol.
	button.SelectionGained.Connect(() => {
		state.hovered = true;
		setActive(state);
		animate(state, HOVER_IN_TI);
	});
	button.SelectionLost.Connect(() => {
		state.hovered = false;
		if (activeState === state) setActive(undefined);
		animate(state, HOVER_OUT_TI);
	});

	button.Destroying.Connect(() => {
		if (activeState === state) setActive(undefined);
		states.delete(button);
	});
}

export function init(): void {
	const gui = Players.LocalPlayer.WaitForChild("PlayerGui");

	for (const desc of gui.GetDescendants()) hook(desc);
	gui.DescendantAdded.Connect(hook);

	// Filet de sécurité : un clic relâché hors du bouton ne déclenche pas
	// MouseButton1Up sur celui-ci. On dépresse alors tout ce qui traîne.
	UserInputService.InputEnded.Connect((input) => {
		if (input.UserInputType !== Enum.UserInputType.MouseButton1 && input.UserInputType !== Enum.UserInputType.Touch) {
			return;
		}
		states.forEach((state) => {
			if (!state.pressed) return;
			state.pressed = false;
			animate(state, RELEASE_TI);
		});
	});
}
