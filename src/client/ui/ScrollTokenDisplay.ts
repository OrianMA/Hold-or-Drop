import { Players, TweenService } from "@rbxts/services";
import { FormatNumber } from "shared/NumberFormat";
import { SCROLL_TOKENS_ATTR } from "shared/QuestConfig";

// Compteur de ScrollToken du panneau des quêtes
// (InGameUI/QuestsPanel/Header/ScrollTokenCount/ScrollCountText) — le pendant de
// MoneyDisplay pour la seconde monnaie, en beaucoup plus simple.
//
// L'attribut ScrollTokens est écrit par le serveur et se réplique ; on ne fait que
// le rendre, en faisant DÉFILER le nombre au lieu de le remplacer d'un coup, pour
// qu'un gain de quête comme une dépense en boutique se voient passer.
//
// `spend(amount)` ajoute la lecture d'une dépense : un « -350K » qui monte et
// s'efface au-dessus du compteur, plus une petite claque d'échelle sur le compteur.
// Le label volant est un CLONE du compteur : il hérite police, taille et contour,
// donc il reste juste même si le style change en Studio.

const player = Players.LocalPlayer;

const LABEL_NAME = "ScrollCountText";
const COUNTER_NAME = "ScrollTokenCount";

// Défilement du nombre. Court : ce n'est pas le compteur d'argent, il ne doit pas
// retenir l'attention aussi longtemps.
const COUNT_TWEEN = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// Claque d'échelle du compteur à la dépense.
const PUNCH_SCALE = 1.18;
const PUNCH_IN = new TweenInfo(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const PUNCH_OUT = new TweenInfo(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

// Label volant « -N ».
const SPEND_COLOR = new Color3(1, 0.45, 0.45);
const SPEND_RISE = 60; // px de montée
const SPEND_TWEEN = new TweenInfo(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

let label: TextLabel | undefined;
let counter: GuiObject | undefined;
let counterScale: UIScale | undefined;
let screenGui: GuiObject | undefined;

let proxy: NumberValue | undefined;
let displayed = 0;
let activeTween: Tween | undefined;

function tokens(): number {
	return (player.GetAttribute(SCROLL_TOKENS_ATTR) as number | undefined) ?? 0;
}

function render(value: number): void {
	displayed = value;
	if (label) label.Text = FormatNumber(math.floor(value));
}

// Fait défiler l'affichage vers la valeur réelle de l'attribut.
function refresh(): void {
	const target = tokens();
	if (!proxy) {
		render(target);
		return;
	}
	activeTween?.Cancel();
	proxy.Value = displayed;
	activeTween = TweenService.Create(proxy, COUNT_TWEEN, { Value: target });
	activeTween.Play();
}

export const ScrollTokenDisplay = {
	init(): void {
		const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI") as GuiObject;
		const header = inGameUI.WaitForChild("QuestsPanel").WaitForChild("Header");
		const counterFrame = header.WaitForChild(COUNTER_NAME) as GuiObject;

		screenGui = inGameUI;
		counter = counterFrame;
		label = counterFrame.WaitForChild(LABEL_NAME) as TextLabel;

		// UIScale posé à la volée côté client (identité à 1 : rien ne bouge tant qu'on
		// ne joue pas la claque).
		const existing = counterFrame.FindFirstChildOfClass("UIScale");
		if (existing) {
			counterScale = existing;
		} else {
			const scale = new Instance("UIScale");
			scale.Parent = counterFrame;
			counterScale = scale;
		}

		proxy = new Instance("NumberValue");
		proxy.Value = tokens();
		proxy.Changed.Connect((value) => render(value));

		render(tokens());
		player.GetAttributeChangedSignal(SCROLL_TOKENS_ATTR).Connect(refresh);
	},

	// Lecture d'une dépense. À appeler APRÈS que le serveur a confirmé l'achat : le
	// défilement du compteur suit l'attribut, ceci n'ajoute que le « -N » volant et la
	// claque.
	spend(amount: number): void {
		if (counterScale) {
			const punchIn = TweenService.Create(counterScale, PUNCH_IN, { Scale: PUNCH_SCALE });
			punchIn.Completed.Connect(() => {
				if (counterScale) TweenService.Create(counterScale, PUNCH_OUT, { Scale: 1 }).Play();
			});
			punchIn.Play();
		}

		if (!label || !counter || !screenGui) return;

		// Clone du compteur : même police, même contour, même taille — aucun style à
		// dupliquer ici.
		const flying = label.Clone();
		flying.Name = "ScrollSpendText";
		flying.Text = `-${FormatNumber(amount)}`;
		flying.TextColor3 = SPEND_COLOR;
		flying.ZIndex = label.ZIndex + 10;
		flying.AutomaticSize = Enum.AutomaticSize.None;

		// Positionné en pixels au-dessus du compteur : le label vit sous le ScreenGui,
		// pas sous le compteur, sinon le UIListLayout du compteur le rangerait dans sa
		// liste et décalerait l'icône.
		const origin = counter.AbsolutePosition.sub(screenGui.AbsolutePosition);
		flying.Size = new UDim2(0, counter.AbsoluteSize.X, 0, counter.AbsoluteSize.Y);
		flying.Position = new UDim2(0, origin.X, 0, origin.Y);
		flying.BackgroundTransparency = 1;
		flying.Parent = screenGui;

		const rise = new UDim2(0, origin.X, 0, origin.Y - SPEND_RISE);
		TweenService.Create(flying, SPEND_TWEEN, { Position: rise, TextTransparency: 1 }).Play();
		for (const child of flying.GetDescendants()) {
			if (child.IsA("UIStroke")) TweenService.Create(child, SPEND_TWEEN, { Transparency: 1 }).Play();
		}
		task.delay(SPEND_TWEEN.Time, () => flying.Destroy());
	},
};
