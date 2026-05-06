import { UiService } from "server/services/UiService";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { Events } from "shared/Event";
import { PopupType } from "shared/PopupType";

export class ButtonModule {
	private playerPosPart!: BasePart;
	private cameraPosPart!: BasePart;
	private proximityPrompt!: ProximityPrompt;
	private baseCash!: number;

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

		this.proximityPrompt.Triggered.Connect((player) => this.onTriggered(player));
	}

	private onTriggered(player: Player) {
		const character = player.Character;
		if (!character) return;

		ButtonSessionService.setSession(player, {
			baseCash: this.baseCash,
			proximityPrompt: this.proximityPrompt,
		});

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
