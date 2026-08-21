import { Players, RunService, Workspace } from "@rbxts/services";
import { FormatNumber } from "shared/NumberFormat";
import {
	QUESTS,
	QUEST_AVAILABLE_LABEL,
	Quest,
	SCROLL_TOKENS_ATTR,
	formatQuestTimer,
	questProgressAttr,
	questResetAttr,
} from "shared/QuestConfig";
import { InGameUIController } from "client/ui/InGameUIController";
import { InformationText } from "client/ui/InformationText";
import { CriticalRain } from "client/ui/CriticalRain";
import { Events } from "shared/Event";

// Ouvre / ferme le panneau des quêtes (InGameUI/QuestsPanel) et le peint.
//   • HUD/ButtonsFrame/QuestsFrame/ImageButton ouvre
//   • Header/CloseButtonFrame/CloseButton ferme
// Ouvrir masque le HUD persistant (même patron que ShopBehavior / DailyRewards).
//
// Tout ce qui s'affiche vient d'attributs répliqués — ScrollTokens pour le compteur
// du header, Q_<id> / QR_<id> pour chaque ligne (voir server/services/QuestService).
// Aucun aller-retour réseau : le client ne fait que lire et peindre.
//
// Une ligne = une Frame de Body/ScrollingFrame, nommée dans shared/QuestConfig :
//   QuestTitletext                        titre de la quête
//   TimeLeftText                          "Enable" ou "Reset in : 4m 32s"
//   ProgressionFrame/CurrentProgressionFrame   barre (taille X en scale, 0..1)
//   ProgressionFrame/TextLabel            "55 / 100"
//   Rewardtext                            "+1.25K"

const player = Players.LocalPlayer;

const POPUP_NAME = "QuestsPanel";

// Célébration d'un accomplissement : bandeau Epic + la pluie d'icônes du Critical
// Claim (même simulation, autre image — voir client/ui/CriticalRain).
const COMPLETE_TEXT = "Quest finish";
const COMPLETE_RAIN_IMAGE = "rbxassetid://17368118782";

// Plus petite largeur de barre affichable : en dessous, le sliver est illisible
// (coins arrondis + contour qui s'écrasent), donc on masque la barre. Même
// raisonnement que la barre de rebirth du HUD.
const MIN_VISIBLE_PROGRESS = 0.013;

// Cadence de rafraîchissement des comptes à rebours, uniquement pendant que le
// panneau est ouvert (fermé, ce code ne coûte rien).
const TIMER_TICK = 1;

interface QuestRow {
	readonly quest: Quest;
	readonly title: TextLabel;
	readonly timeLeft: TextLabel;
	readonly fill: Frame;
	readonly progressText: TextLabel;
	readonly reward: TextLabel;
}

function scrollTokens(): number {
	return (player.GetAttribute(SCROLL_TOKENS_ATTR) as number | undefined) ?? 0;
}

function questProgress(quest: Quest): number {
	return (player.GetAttribute(questProgressAttr(quest.id)) as number | undefined) ?? 0;
}

// Instant de reset en temps serveur ; 0 = quête disponible.
function questResetAt(quest: Quest): number {
	return (player.GetAttribute(questResetAttr(quest.id)) as number | undefined) ?? 0;
}

// Résout une ligne. FindFirstChild (et non WaitForChild) partout : une Frame
// absente ou mal nommée doit coûter UNE ligne de quête, jamais le blocage de tous
// les init clients qui suivent dans main.client.ts.
function readRow(scrollingFrame: Instance, quest: Quest): QuestRow | undefined {
	const frame = scrollingFrame.FindFirstChild(quest.frameName);
	if (!frame) {
		warn(`QuestsBehavior: ${quest.frameName} introuvable — quête ${quest.id} non affichée`);
		return undefined;
	}

	const title = frame.FindFirstChild("QuestTitletext");
	const timeLeft = frame.FindFirstChild("TimeLeftText");
	const progressionFrame = frame.FindFirstChild("ProgressionFrame");
	const fill = progressionFrame?.FindFirstChild("CurrentProgressionFrame");
	const progressText = progressionFrame?.FindFirstChild("TextLabel");
	const reward = frame.FindFirstChild("Rewardtext");

	if (
		!title?.IsA("TextLabel") ||
		!timeLeft?.IsA("TextLabel") ||
		!fill?.IsA("Frame") ||
		!progressText?.IsA("TextLabel") ||
		!reward?.IsA("TextLabel")
	) {
		warn(`QuestsBehavior: ${quest.frameName} incomplet — quête ${quest.id} non affichée`);
		return undefined;
	}

	return { quest, title, timeLeft, fill, progressText, reward };
}

// Le compte à rebours est la seule partie qui bouge sans changement d'attribut :
// il est réécrit à chaque tick tant que le panneau est ouvert.
function renderTimer(row: QuestRow): void {
	const resetAt = questResetAt(row.quest);
	if (resetAt <= 0) {
		row.timeLeft.Text = QUEST_AVAILABLE_LABEL;
		return;
	}
	row.timeLeft.Text = formatQuestTimer(resetAt - Workspace.GetServerTimeNow());
}

function renderRow(row: QuestRow): void {
	const { quest } = row;
	const current = math.min(questProgress(quest), quest.target);

	row.title.Text = quest.title;
	row.reward.Text = `+${FormatNumber(quest.reward)}`;
	row.progressText.Text = `${FormatNumber(math.floor(current))} / ${FormatNumber(quest.target)}`;

	const progress = math.clamp(current / quest.target, 0, 1);
	if (progress < MIN_VISIBLE_PROGRESS) {
		row.fill.Visible = false;
	} else {
		row.fill.Visible = true;
		row.fill.Size = new UDim2(progress, 0, 1, 0);
	}

	renderTimer(row);
}

export function init(): void {
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");

	const popup = inGameUI.WaitForChild(POPUP_NAME) as GuiObject;
	const header = popup.WaitForChild("Header");
	const closeButton = header.WaitForChild("CloseButtonFrame").WaitForChild("CloseButton") as GuiButton;
	const tokenText = header.WaitForChild("ScrollTokenCount").WaitForChild("ScrollCountText") as TextLabel;
	const scrollingFrame = popup.WaitForChild("Body").WaitForChild("ScrollingFrame");

	const hud = inGameUI.WaitForChild("HUD") as GuiObject;
	const openButton = hud
		.WaitForChild("ButtonsFrame")
		.WaitForChild("QuestsFrame")
		.WaitForChild("ImageButton") as GuiButton;

	popup.Visible = false; // start hidden regardless of the Studio default

	const rows: QuestRow[] = [];
	for (const quest of QUESTS) {
		const row = readRow(scrollingFrame, quest);
		if (row) rows.push(row);
	}

	const renderTokens = (): void => {
		tokenText.Text = FormatNumber(scrollTokens());
	};

	const renderAll = (): void => {
		renderTokens();
		for (const row of rows) renderRow(row);
	};

	let timerLoop: RBXScriptConnection | undefined;
	let sinceTick = 0;

	const open = (): void => {
		renderAll();
		popup.Visible = true;
		InGameUIController.disable();

		timerLoop?.Disconnect();
		sinceTick = TIMER_TICK; // premier rafraîchissement immédiat
		timerLoop = RunService.Heartbeat.Connect((delta) => {
			sinceTick += delta;
			if (sinceTick < TIMER_TICK) return;
			sinceTick = 0;
			for (const row of rows) renderTimer(row);
		});
	};

	const close = (): void => {
		popup.Visible = false;
		InGameUIController.enable();
		timerLoop?.Disconnect();
		timerLoop = undefined;
	};

	openButton.Activated.Connect(open);
	closeButton.Activated.Connect(close);

	// Le serveur pousse la progression et les cooldowns par attributs : on ne repeint
	// que la ligne concernée, et seulement si le panneau est à l'écran (fermé, l'état
	// est de toute façon relu à l'ouverture).
	for (const row of rows) {
		for (const attribute of [questProgressAttr(row.quest.id), questResetAttr(row.quest.id)]) {
			player.GetAttributeChangedSignal(attribute).Connect(() => {
				if (popup.Visible) renderRow(row);
			});
		}
	}

	// Le compteur de tokens, lui, se met à jour même panneau fermé : il est bon marché
	// et évite tout décalage à l'ouverture suivante.
	player.GetAttributeChangedSignal(SCROLL_TOKENS_ATTR).Connect(renderTokens);

	// Quête accomplie : le serveur a déjà versé la récompense et publié l'état, cet
	// event ne sert qu'à la célébration.
	CriticalRain.preload(COMPLETE_RAIN_IMAGE);
	Events.QuestCompletedEvent.OnClientEvent.Connect(() => {
		InformationText.show(COMPLETE_TEXT, { rarity: "Epic" });
		CriticalRain.play(COMPLETE_RAIN_IMAGE);
	});

	renderAll();
}
