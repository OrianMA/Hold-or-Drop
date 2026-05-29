import { UiService } from "server/services/UiService";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { PlayerDataService } from "server/services/PlayerDataService";
import { Events } from "shared/Event";
import { PopupType } from "shared/PopupType";
import { FormatCash } from "shared/NumberFormat";

const NOT_ENOUGH_MONEY_TEXT = "Not enough money";
const NOT_ENOUGH_MONEY_COLOR = new Color3(1, 0.25, 0.25); // red
const NOT_ENOUGH_MONEY_HOLD = 2.5; // seconds — longer than the default flash so the player actually reads it

const UI_PART_NAME = "UiPart";
const BILLBOARD_NAME = "BillboardGui";
const GAIN_LABEL = "GainText";
const COST_LABEL = "CostText";
const POSSESSED_TEXT = "POSSESSED";

export class ButtonModule {
	private playerPosPart!: BasePart;
	private cameraPosPart!: BasePart;
	private proximityPrompt!: ProximityPrompt;
	private billboardGui: BillboardGui | undefined;
	private baseCash!: number;
	private cost!: number;
	private dataName!: string;

	init(model: Instance) {
		this.playerPosPart = model.FindFirstChild("PlayerPosPlaceHolder") as BasePart;
		this.cameraPosPart = model.FindFirstChild("CameraPosPart") as BasePart;
		this.proximityPrompt = model
			.FindFirstChild("ButtonPart")
			?.FindFirstChildOfClass("ProximityPrompt") as ProximityPrompt;

		if (!this.playerPosPart || !this.cameraPosPart || !this.proximityPrompt) {
			warn(`ButtonModule: Missing parts in ${model.Name}`);
			return;
		}

		this.baseCash = (model.GetAttribute("BaseCash") as number) ?? 10000;
		this.cost = (model.GetAttribute("Cost") as number) ?? 0;
		// DataName is the persistence key — falls back to model name so the
		// system still works if the attribute hasn't been authored yet.
		this.dataName = (model.GetAttribute("DataName") as string) ?? model.Name;

		const uiPart = model.FindFirstChild(UI_PART_NAME);
		const billboard = uiPart?.FindFirstChild(BILLBOARD_NAME);
		if (billboard?.IsA("BillboardGui")) this.billboardGui = billboard;

		// Initial UI sync — server-side property writes replicate to all
		// clients, so the labels show the right values from the very first
		// frame instead of whatever was authored in Studio. The "POSSESSED"
		// override for unlocked players still happens client-side
		// (ButtonLabelsController) since that's per-player state.
		this.syncLabels(model);
		this.proximityPrompt.ObjectText = `${FormatCash(this.baseCash)} money`;

		this.proximityPrompt.Triggered.Connect((player) => this.onTriggered(player));
	}

	private syncLabels(model: Instance): void {
		const uiPart = model.FindFirstChild(UI_PART_NAME);
		if (!uiPart) return;

		const gainLabel = uiPart.FindFirstChild(GAIN_LABEL, true);
		if (gainLabel?.IsA("TextLabel")) gainLabel.Text = FormatCash(this.baseCash);

		const costLabel = uiPart.FindFirstChild(COST_LABEL, true);
		// Default = "locked" state. Client overrides to "POSSESSED" per-player.
		// Free buttons (cost <= 0) are always owned — show POSSESSED to everyone.
		if (costLabel?.IsA("TextLabel")) {
			costLabel.Text = this.cost <= 0 ? POSSESSED_TEXT : `${FormatCash(this.cost)} money`;
		}
	}

	private onTriggered(player: Player) {
		const character = player.Character;
		if (!character) return;

		// ── Purchase gate ─────────────────────────────────────────────────────
		// If the player hasn't unlocked this button, this trigger is an attempt
		// to buy it.
		//   • Free buttons (cost <= 0) skip the gate entirely — owned by default.
		//   • Not enough money → flash the info text and bail out.
		//   • Enough money     → debit, flag as owned, and stop — the trigger
		//     just completed the purchase. The player has to interact with the
		//     button a second time to actually enter the game.
		if (this.cost > 0 && !PlayerDataService.isButtonUnlocked(player, this.dataName)) {
			const money = PlayerDataService.get(player, "Money");
			if (money < this.cost) {
				Events.InformationTextEvent.FireClient(
					player,
					NOT_ENOUGH_MONEY_TEXT,
					NOT_ENOUGH_MONEY_COLOR,
					NOT_ENOUGH_MONEY_HOLD,
				);
				return;
			}
			PlayerDataService.add(player, "Money", -this.cost);
			PlayerDataService.setButtonUnlocked(player, this.dataName);
			return;
		}

		ButtonSessionService.setSession(player, {
			baseCash: this.baseCash,
			proximityPrompt: this.proximityPrompt,
			billboardGui: this.billboardGui,
		});

		// Hide the floating label-billboard for the active player only — restored
		// when ButtonSessionService.cleanup() runs at the end of the session.
		if (this.billboardGui) this.billboardGui.PlayerToHideFrom = player;

		Events.ButtonTriggerEvent.FireClient(player, this.cameraPosPart);

		this.teleportPlayer(character);
		this.proximityPrompt.Enabled = false;

		UiService.Show(player, PopupType.ButtonMenu);
	}

	private teleportPlayer(character: Model) {
		const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
		if (!hrp) return;

		const playerSize = character.GetExtentsSize().Y;
		hrp.CFrame = this.playerPosPart.CFrame.add(new Vector3(0, playerSize / 2, 0));
		hrp.Anchored = true;
	}
}
