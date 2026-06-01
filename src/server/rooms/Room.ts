import { FormatCash } from "shared/NumberFormat";

// A Room wraps one Workspace/PlayerZones/P{n} folder and the ButtonModel it
// contains. It resolves the model's parts once, tracks which player (if any)
// currently owns the room, and drives the per-room UI (billboard + prompt text).
//
// Ownership is the core access rule: only the assigned occupant may trigger the
// room's button. Empty rooms have their ProximityPrompt disabled and show
// "Empty" on the billboard.

const BUTTON_MODEL = "ButtonModel";
const BUTTON_PART = "ButtonPart";
const PLAYER_POS_PART = "PlayerPosPlaceHolder";
const CAMERA_POS_PART = "CameraPosPart";
const UI_PART = "UiPart";
const BILLBOARD = "BillboardGui";
const GAIN_LABEL = "GainText";
const EMPTY_TEXT = "Empty";

export class Room {
	readonly name: string;
	readonly folder: Instance;
	readonly buttonModel!: Model;
	readonly proximityPrompt!: ProximityPrompt;
	readonly buttonPart!: BasePart;
	readonly playerPosPart!: BasePart;
	readonly cameraPosPart!: BasePart;
	readonly billboardGui: BillboardGui | undefined;

	private gainLabel: TextLabel | undefined;
	private occupant: Player | undefined;
	private valid = true;

	constructor(folder: Instance) {
		this.name = folder.Name;
		this.folder = folder;

		const buttonModel = folder.FindFirstChild(BUTTON_MODEL);
		if (!buttonModel || !buttonModel.IsA("Model")) {
			this.invalidate(`missing ${BUTTON_MODEL}`);
			return;
		}
		this.buttonModel = buttonModel;

		const buttonPart = buttonModel.FindFirstChild(BUTTON_PART);
		const proximityPrompt = buttonPart?.FindFirstChildOfClass("ProximityPrompt");
		const playerPosPart = buttonModel.FindFirstChild(PLAYER_POS_PART);
		const cameraPosPart = buttonModel.FindFirstChild(CAMERA_POS_PART);

		if (
			!buttonPart ||
			!buttonPart.IsA("BasePart") ||
			!proximityPrompt ||
			!playerPosPart ||
			!playerPosPart.IsA("BasePart") ||
			!cameraPosPart ||
			!cameraPosPart.IsA("BasePart")
		) {
			this.invalidate("missing button parts");
			return;
		}

		this.buttonPart = buttonPart;
		this.proximityPrompt = proximityPrompt;
		this.playerPosPart = playerPosPart;
		this.cameraPosPart = cameraPosPart;

		// Billboard is optional — gameplay still works without it.
		const billboard = buttonModel.FindFirstChild(UI_PART)?.FindFirstChild(BILLBOARD);
		if (billboard?.IsA("BillboardGui")) {
			this.billboardGui = billboard;
			const label = billboard.FindFirstChild(GAIN_LABEL, true);
			if (label?.IsA("TextLabel")) this.gainLabel = label;
		}
	}

	private invalidate(reason: string): void {
		this.valid = false;
		warn(`Room ${this.name}: ${reason} — room ignored`);
	}

	isValid(): boolean {
		return this.valid;
	}

	isEmpty(): boolean {
		return this.occupant === undefined;
	}

	getOccupant(): Player | undefined {
		return this.occupant;
	}

	owns(player: Player): boolean {
		return this.occupant === player;
	}

	// Mark the room as owned by `player` and enable its button.
	assign(player: Player): void {
		this.occupant = player;
		this.proximityPrompt.Enabled = true;
	}

	// Free the room: disable the button and reset the billboard to "Empty".
	release(): void {
		this.occupant = undefined;
		this.proximityPrompt.Enabled = false;
		this.proximityPrompt.ObjectText = EMPTY_TEXT;
		if (this.gainLabel) this.gainLabel.Text = EMPTY_TEXT;
	}

	// Display the occupant's BaseCash on the billboard + proximity prompt.
	setGainCash(cash: number): void {
		if (this.gainLabel) this.gainLabel.Text = FormatCash(cash);
		this.proximityPrompt.ObjectText = `${FormatCash(cash)} money`;
	}
}
