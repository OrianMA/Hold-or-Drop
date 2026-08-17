import { Players } from "@rbxts/services";

// Le ScreenGui du tutorial, créé 100 % en code (rien à authorer dans Studio sauf le
// bouton Skip — voir TutorialSkipButton). Contient l'overlay de focus, les flèches et
// le bandeau d'instruction. Détruit intégralement à la fin du tutorial.

const GUI_NAME = "TutorialUI";
const IN_GAME_UI = "InGameUI";
// Au-dessus de InGameUI (qui n'a pas de DisplayOrder explicite, donc 0).
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
		// Placement mesuré dans Studio (viewport 1627x905) pour ne recouvrir AUCUN élément
		// du jeu, run en cours ou pas :
		//   • verticalement, la bande y ∈ [0.22, 0.29] passe sous le MultiplierText
		//     (y 36→147) et au-dessus des boutons Start (457) / Claim (639) et de
		//     HUD/BottomList (715→797) ;
		//   • horizontalement, la colonne gauche du HUD (MoneyParent puis ButtonsFrame /
		//     Rebirth) occupe x 21→390 de y 122 à 620 — d'où une largeur de 0.52 centrée
		//     (x 390→1236 ici) plutôt que pleine largeur.
		// Ces deux nombres sont les seuls leviers de placement : les retoucher ne demande
		// aucun autre changement.
		frame.AnchorPoint = new Vector2(0.5, 0);
		frame.Position = new UDim2(0.5, 0, 0.22, 0);
		frame.Size = new UDim2(0.52, 0, 0, 64);
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
