import { Players } from "@rbxts/services";

// Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
// bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
// le bandeau d'instruction. Détruit intégralement à la fin du tutorial.

const GUI_NAME = "TutorialUI";
const IN_GAME_UI = "InGameUI";
// Au-dessus de InGameUI (mesuré à DisplayOrder = 1).
const DISPLAY_ORDER = 100;

let screenGui: ScreenGui | undefined;
let banner: Frame | undefined;
let label: TextLabel | undefined;

function playerGui(): PlayerGui {
	return Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui;
}

export const TutorialUI = {
	// Le ScreenGui du jeu — sert de référence de coordonnées (même GuiInset) et de
	// racine pour résoudre les cibles GUI.
	getInGameUI(): ScreenGui | undefined {
		const found = playerGui().FindFirstChild(IN_GAME_UI);
		return found?.IsA("ScreenGui") ? found : undefined;
	},

	ensure(): ScreenGui {
		if (screenGui && screenGui.Parent !== undefined) return screenGui;

		const gui = new Instance("ScreenGui");
		gui.Name = GUI_NAME;
		gui.ResetOnSpawn = false;
		gui.DisplayOrder = DISPLAY_ORDER;
		// Aligner l'inset sur celui du GUI du jeu, sinon tous les rectangles de cible
		// seraient décalés de la hauteur de la barre Roblox.
		gui.IgnoreGuiInset = TutorialUI.getInGameUI()?.IgnoreGuiInset ?? false;
		gui.Parent = playerGui();
		screenGui = gui;

		const frame = new Instance("Frame");
		frame.Name = "InstructionBanner";
		// Placement ENTIÈREMENT en scale — position ET taille — pour que le rectangle occupe
		// la même fraction d'écran partout (le jeu est mobile-first, et le paysage
		// téléphone descend vers 375 px de haut). Le moindre offset en pixels rendrait la
		// marge dépendante de la hauteur du viewport : avec une hauteur fixe de 64 px, le
		// bas du bandeau touchait le bouton Start dès que la hauteur d'écran passait sous
		// ~388 px.
		//
		// Bandes occupées par le jeu, mesurées dans Studio et exprimées en fractions :
		//   MoneyParent   y 0.21→0.29  (sa LARGEUR dépend d'un UIAspectRatioConstraint,
		//                               donc du viewport : seule sa bande verticale est fiable)
		//   ButtonsFrame  x 0.013→0.24, y 0.31→0.75   (scale pur)
		//   StartButton   y 0.505→0.605
		//   Claim/Result  y 0.71→0.84
		//   BottomList    y 0.855→0.945              (scale pur)
		// Le bandeau tient donc dans x 0.27→0.73 et y 0.34→0.42 : sous MoneyParent, au-dessus
		// de Start, et à 3 points de la colonne ButtonsFrame. Ces trois nombres (Y, largeur,
		// hauteur) sont les seuls leviers — les garder en scale, jamais en offset.
		frame.AnchorPoint = new Vector2(0.5, 0);
		frame.Position = new UDim2(0.5, 0, 0.34, 0);
		frame.Size = new UDim2(0.46, 0, 0.08, 0);
		frame.BackgroundColor3 = Color3.fromRGB(12, 12, 20);
		frame.BackgroundTransparency = 0.25;
		frame.BorderSizePixel = 0;
		frame.Visible = false;
		frame.Parent = gui;
		banner = frame;

		const corner = new Instance("UICorner");
		corner.CornerRadius = new UDim(0, 12);
		corner.Parent = frame;

		const stroke = new Instance("UIStroke");
		stroke.Thickness = 2;
		stroke.Color = Color3.fromRGB(255, 255, 255);
		stroke.Transparency = 0.5;
		stroke.Parent = frame;

		const text = new Instance("TextLabel");
		text.Name = "InstructionText";
		text.BackgroundTransparency = 1;
		text.Size = new UDim2(1, -24, 1, -12);
		text.Position = new UDim2(0, 12, 0, 6);
		text.Font = Enum.Font.GothamBold;
		text.TextScaled = true;
		text.TextColor3 = new Color3(1, 1, 1);
		text.TextWrapped = true;
		text.Text = "";
		text.Parent = frame;
		label = text;

		const textSize = new Instance("UITextSizeConstraint");
		textSize.MaxTextSize = 22;
		textSize.Parent = text;

		return gui;
	},

	setText(value: string): void {
		TutorialUI.ensure();
		if (!banner || !label) return;
		label.Text = value;
		banner.Visible = value !== "";
	},

	hideBanner(): void {
		if (banner) banner.Visible = false;
	},

	destroy(): void {
		if (screenGui) screenGui.Destroy();
		screenGui = undefined;
		banner = undefined;
		label = undefined;
	},
};
