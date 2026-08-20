import { MarketplaceService, Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { FormatCash } from "shared/NumberFormat";
import {
	DAILY_AUTO_OPEN_ATTR,
	DAILY_CLAIMED_ATTR,
	DAILY_MULTIPLIER_ATTR,
	DAILY_X3_PRODUCT_ID,
} from "shared/DailyRewardConfig";
import { InGameUIController } from "client/ui/InGameUIController";
import { MoneyBurst } from "client/ui/MoneyBurst";
import { FloatingReward } from "client/ui/FloatingReward";
import { playCashSound } from "client/audio/CashSound";
import { InformationText } from "client/ui/InformationText";
import { DailyRewardsAnimation, DailyRewardsRefs } from "client/ui/DailyRewardsAnimation";
import { TutorialUI } from "client/tutorial/TutorialUI";

// Opens / closes the daily reward popup (InGameUI/DailyRewards) and renders it.
//   • HUD/ButtonsFrame/DailyRewardsFrame/ImageButton opens it at any time.
//   • the replicated DailyAutoOpen attribute opens it by itself — on join with a
//     pending reward, or on the first rebirth of a brand-new player.
//   • Header/CloseButtonFrame/CloseButton closes it.
// Opening hides the persistent HUD (mirrors ShopBehavior / RebirthMenuBehavior).
//
// Everything shown is read from the replicated attributes DailyMultiplier /
// DailyClaimed + EffectiveBaseCash — no round-trip. The grant itself is fully
// re-validated server-side (DailyRewardService).

const POPUP_NAME = "DailyRewards";
const CLAIMED_LABEL = "Claimed";

// Menus the popup takes the screen from when it opens by itself. The first-rebirth
// auto-open in particular lands while the Rebirth menu is still up — leaving it
// behind would restore the HUD on top of it when the popup closes. They are plain
// open/close frames with no state of their own, so hiding them here is safe.
const MENUS_TO_HIDE = ["RebirthMenu", "ShopMenu", "ShopMoneyBuy"];

// Une ouverture AUTOMATIQUE ne vole pas l'écran à un menu que le joueur est en train
// de lire : elle attend qu'il le referme, puis laisse passer ce temps mort avant de
// s'afficher. Le cas qui compte est le premier rebirth — le popup est déclenché
// pendant que le menu Rebirth est encore ouvert sur l'écran de résultat.
const AUTO_OPEN_AFTER_MENU_DELAY = 1.5;
const MENU_POLL = 0.2;

// Greyed-out tint applied to a button while today's reward is already taken.
const DISABLED_COLOR = new Color3(0.45, 0.45, 0.45);

const REWARD_COLOR = new Color3(0.45, 1, 0.55);

interface ClaimButton {
	button: TextButton;
	label: TextLabel;
	baseColor: Color3;
	baseText: string;
}

function readButton(frame: Instance): ClaimButton {
	const button = frame.WaitForChild("Button") as TextButton;
	const label = button.WaitForChild("TextLabel") as TextLabel;
	return { button, label, baseColor: button.BackgroundColor3, baseText: label.Text };
}

// Enabled = the authored colour + text; disabled = grey, non-interactive, "Claimed"
// on the free button (the ×3 keeps its own label — it just can't be bought again today).
function setEnabled(entry: ClaimButton, enabled: boolean, claimedLabel?: string): void {
	entry.button.Interactable = enabled;
	entry.button.AutoButtonColor = enabled;
	entry.button.BackgroundColor3 = enabled ? entry.baseColor : DISABLED_COLOR;
	entry.label.Text = enabled ? entry.baseText : (claimedLabel ?? entry.baseText);
}

export function init(): void {
	const player = Players.LocalPlayer;
	const inGameUI = (player.WaitForChild("PlayerGui") as PlayerGui).WaitForChild("InGameUI");

	const popup = inGameUI.WaitForChild(POPUP_NAME) as GuiObject;
	const closeButton = popup
		.WaitForChild("Header")
		.WaitForChild("CloseButtonFrame")
		.WaitForChild("CloseButton") as GuiButton;

	const header = popup.WaitForChild("Header") as GuiObject;
	const body = popup.WaitForChild("Body");
	const dailyCashTitle = body.WaitForChild("DailyCashTitle") as TextLabel;
	const dailyCashValue = body.WaitForChild("DailyCashValue") as TextLabel;
	const baseCashTitle = body.WaitForChild("BaseCashTitle") as TextLabel;
	const baseCashValue = body.WaitForChild("BaseCashValue") as TextLabel;
	const multiplierTitle = body.WaitForChild("DailyBonusMultiplierTitle") as TextLabel;
	const multiplierValue = body.WaitForChild("DailyBonusMultiplierValue") as TextLabel;

	const buttonsFrame = popup.WaitForChild("ButtonsFrame");
	const claimFrame = buttonsFrame.WaitForChild("ClaimButtonFrame") as GuiObject;
	const claimX3Frame = buttonsFrame.WaitForChild("X3ClaimButtonFrame") as GuiObject;
	const claim = readButton(claimFrame);
	const claimX3 = readButton(claimX3Frame);

	// Everything the opening animation cascades in, in authored order — it re-sorts
	// them by their real vertical position (see DailyRewardsAnimation.sortKey).
	const refs: DailyRewardsRefs = {
		popup,
		rows: [
			header,
			dailyCashTitle,
			dailyCashValue,
			baseCashValue,
			baseCashTitle,
			multiplierValue,
			multiplierTitle,
			claimFrame,
			claimX3Frame,
		],
		totalLabel: dailyCashValue,
		multiplierLabel: multiplierValue,
	};

	const hud = inGameUI.WaitForChild("HUD") as GuiObject;
	const openButton = hud
		.WaitForChild("ButtonsFrame")
		.WaitForChild("DailyRewardsFrame")
		.WaitForChild("ImageButton") as GuiButton;

	popup.Visible = false; // start hidden regardless of the Studio default

	const multiplier = (): number => (player.GetAttribute(DAILY_MULTIPLIER_ATTR) as number | undefined) ?? 1;
	const baseCash = (): number => (player.GetAttribute("EffectiveBaseCash") as number | undefined) ?? 0;
	const claimed = (): boolean => player.GetAttribute(DAILY_CLAIMED_ATTR) === true;

	// Writes the three numbers + the button states from the current attributes.
	// Called on open and whenever the server changes them while the popup is up.
	const render = (): void => {
		const mult = multiplier();
		const base = baseCash();
		baseCashValue.Text = `$${FormatCash(base)}`;
		multiplierValue.Text = `${mult}x`;
		dailyCashValue.Text = `$${FormatCash(math.floor(base * mult))}`;

		const available = !claimed();
		setEnabled(claim, available, CLAIMED_LABEL);
		setEnabled(claimX3, available);
	};

	const animationValues = (): { baseCash: number; multiplier: number; animateCounters: boolean } => ({
		baseCash: baseCash(),
		multiplier: multiplier(),
		// Already claimed → the popup still cascades in, but the counters don't replay.
		animateCounters: !claimed(),
	});

	const open = (): void => {
		for (const name of MENUS_TO_HIDE) {
			const menu = inGameUI.FindFirstChild(name);
			if (menu?.IsA("GuiObject")) menu.Visible = false;
		}
		render();
		popup.Visible = true;
		InGameUIController.disable();
		// The popup can land mid-tutorial (a returning player who never finished it):
		// hide the tutorial overlay so its dim doesn't darken the popup.
		TutorialUI.setSuppressed(true);
		DailyRewardsAnimation.play(refs, animationValues());
	};

	const close = (): void => {
		// Drop a running sequence first, otherwise a row could stay half-faded the
		// next time the popup shows.
		DailyRewardsAnimation.stop(refs, animationValues());
		popup.Visible = false;
		InGameUIController.enable();
		TutorialUI.setSuppressed(false);
	};

	openButton.Activated.Connect(open);
	closeButton.Activated.Connect(close);

	// Le joueur est-il revenu à un écran neutre ? Aucun menu ouvert ET le HUD affiché.
	// Après un rebirth le menu Rebirth reste ouvert et le HUD est masqué : le popup
	// attend que le joueur ait refermé et soit bien retombé sur son HUD.
	const backOnHud = (): boolean => {
		if (!hud.Visible) return false;
		for (const name of MENUS_TO_HIDE) {
			const menu = inGameUI.FindFirstChild(name);
			if (menu?.IsA("GuiObject") && menu.Visible) return false;
		}
		return true;
	};

	// Auto-open : le serveur incrémente DailyAutoOpen quand il veut voir le popup —
	// avant qu'on arrive ici (connexion) ou plus tard (premier rebirth). On ouvre dès
	// que le compteur dépasse celui qu'on a déjà traité, ce qui donne le "une fois par
	// demande" sans latch : le serveur ne demande qu'une fois.
	let handledToken = 0;
	const autoOpen = (): void => {
		const token = (player.GetAttribute(DAILY_AUTO_OPEN_ATTR) as number | undefined) ?? 0;
		if (token <= handledToken) return;
		handledToken = token;
		task.spawn(() => {
			if (!backOnHud()) {
				while (!backOnHud()) task.wait(MENU_POLL);
				task.wait(AUTO_OPEN_AFTER_MENU_DELAY);
			}
			open();
		});
	};
	player.GetAttributeChangedSignal(DAILY_AUTO_OPEN_ATTR).Connect(autoOpen);
	autoOpen();

	claim.button.Activated.Connect(() => {
		if (claimed()) return;
		// Lock both buttons right away: the attribute only flips once the server
		// answers, and a double click would fire the event twice.
		setEnabled(claim, false, CLAIMED_LABEL);
		setEnabled(claimX3, false);
		Events.DailyRewardClaimEvent.FireServer();
	});

	claimX3.button.Activated.Connect(() => {
		if (claimed()) return;
		MarketplaceService.PromptProductPurchase(player, DAILY_X3_PRODUCT_ID);
	});

	// Centre du compteur d'argent du HUD, en coordonnées écran absolues — la cible vers
	// laquelle les billets convergent. Résolue au moment de l'aspiration : le HUD est
	// masqué pendant que le popup est ouvert, il est de retour quand les billets partent.
	const moneyCounterCenter = (): Vector2 | undefined => {
		const moneyParent = InGameUIController.getMoneyParent();
		if (!moneyParent) return undefined;
		return moneyParent.AbsolutePosition.add(moneyParent.AbsoluteSize.div(2));
	};

	// Server confirmed the grant (free claim or ×3 receipt): close the popup and
	// flash what was earned.
	Events.DailyRewardGrantedEvent.OnClientEvent.Connect((amount: number, mult: number, bonus: number) => {
		// A ×3 receipt can land after the player closed the popup — only take the
		// screen back if we still own it.
		if (popup.Visible) close();

		// Exactement la gerbe de billets du claim (§6.21) + son son de cash, à ceci
		// près qu'ici les billets finissent aspirés dans le compteur d'argent.
		playCashSound();
		MoneyBurst.play(undefined, { gatherTo: moneyCounterCenter });
		// Et le même "+montant" léger que la récompense de consolation d'une explosion
		// (§6.4) — en version sans crédit : le serveur a déjà encaissé le gain.
		FloatingReward.showAlreadyCredited(amount, "fly");
		const suffix = bonus > 1 ? ` (x${mult} x${bonus})` : ` (x${mult})`;
		InformationText.show(`Daily reward +$${FormatCash(amount)}${suffix}`, { color: REWARD_COLOR });
	});

	// Keep an open popup in sync if the numbers move underneath it. This is not
	// theoretical: BoostService resolves group + game-pass ownership asynchronously,
	// so EffectiveBaseCash routinely lands a second after join — right while the
	// auto-opened popup is revealing. Re-running the whole sequence (rather than just
	// rewriting the labels) keeps the count-up aiming at the right total.
	let shown = `${baseCash()}|${multiplier()}|${claimed()}`;
	for (const attribute of [DAILY_CLAIMED_ATTR, DAILY_MULTIPLIER_ATTR, "EffectiveBaseCash"]) {
		player.GetAttributeChangedSignal(attribute).Connect(() => {
			const current = `${baseCash()}|${multiplier()}|${claimed()}`;
			if (current === shown) return;
			shown = current;
			if (!popup.Visible) return;
			render();
			DailyRewardsAnimation.play(refs, animationValues());
		});
	}
}
