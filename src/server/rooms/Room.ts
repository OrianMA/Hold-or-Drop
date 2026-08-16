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
// Camera parts live in the MovableModel (the rocket rig), not the ButtonModel:
// CameraPosPart is the camera's start pose, CameraParentPart the orbit pivot the
// camera always faces (see CameraController.StartOrbit).
const MOVABLE_MODEL = "MovableModel";
const CAMERA_POS_PART = "CameraPosPart";
const CAMERA_PIVOT_PART = "CameraParentPart";
// Invisible marker the rocket is positioned onto (RocketPlacer seats the cloned
// rocket here on assign — see RocketPlacer).
const ROCKET_SPAWN_POINT = "RocketSpawnPoint";
const UI_PART = "UiPart";
const BILLBOARD = "BillboardGui";
const GAIN_LABEL = "GainText";
const EMPTY_TEXT = "Empty";
const EMPTY_BASE_TEXT = "Empty base";
// Accepted names for the per-room spawn marker (a plain Part, not a SpawnLocation).
// Add yours here if you rename it.
const SPAWN_PART_NAMES = ["RespawnLocation", "SpawnLocation", "SpawnPart"];
// Owner-display model — sibling of the ButtonModel inside the room folder.
// Shows the occupant's name on a SurfaceGui and a "your base" BillboardGui that
// is enabled client-side only for the owning player (see OwnerIndicatorController).
const OWNER_DISPLAY = "OwnerDisplay";
const NAME_PART = "NamePart";
const NAME_TEXT_LABEL = "NameText";
const OWNER_INDICATOR_PART = "OwnerIndicatorPart";

export class Room {
	readonly name: string;
	readonly folder: Instance;
	readonly buttonModel!: Model;
	readonly movableModel!: Model;
	readonly proximityPrompt!: ProximityPrompt;
	readonly buttonPart!: BasePart;
	readonly playerPosPart!: BasePart;
	readonly cameraPosPart!: BasePart;
	readonly cameraPivotPart!: BasePart;
	// Where RocketPlacer seats the rocket on assign. Optional: a room without it
	// simply gets no rocket (warned), rather than being invalidated entirely.
	readonly rocketSpawnPoint: BasePart | undefined;
	readonly billboardGui: BillboardGui | undefined;
	// The room's spawn marker — the occupant is teleported here on every spawn.
	// A plain Part is fine (it's not used as a real SpawnLocation). Optional.
	readonly spawnPart: BasePart | undefined;

	private gainLabel: TextLabel | undefined;
	private ownerNameLabel: TextLabel | undefined;
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

		if (
			!buttonPart ||
			!buttonPart.IsA("BasePart") ||
			!proximityPrompt ||
			!playerPosPart ||
			!playerPosPart.IsA("BasePart")
		) {
			this.invalidate("missing button parts");
			return;
		}

		// Camera parts live in the MovableModel (rocket rig), not the ButtonModel.
		const movableModel = folder.FindFirstChild(MOVABLE_MODEL);
		const cameraPosPart = movableModel?.FindFirstChild(CAMERA_POS_PART);
		const cameraPivotPart = movableModel?.FindFirstChild(CAMERA_PIVOT_PART);

		if (
			!movableModel ||
			!movableModel.IsA("Model") ||
			!cameraPosPart ||
			!cameraPosPart.IsA("BasePart") ||
			!cameraPivotPart ||
			!cameraPivotPart.IsA("BasePart")
		) {
			this.invalidate(`missing ${MOVABLE_MODEL} camera parts`);
			return;
		}

		this.buttonPart = buttonPart;
		this.proximityPrompt = proximityPrompt;
		this.playerPosPart = playerPosPart;
		this.movableModel = movableModel;
		this.cameraPosPart = cameraPosPart;
		this.cameraPivotPart = cameraPivotPart;

		// ProximityPrompt.Enabled is a global property — there's no per-player
		// toggle. We keep it disabled on the server and let each client enable only
		// the prompt for the room they own (client-side writes don't replicate). See
		// RoomPromptController. The server never flips Enabled again, so the client's
		// local override is never stomped.
		this.proximityPrompt.Enabled = false;

		// Rocket spawn marker (optional). RocketPlacer seats the cloned rocket
		// onto it when the room is assigned.
		const spawnPoint = movableModel.FindFirstChild(ROCKET_SPAWN_POINT);
		if (spawnPoint?.IsA("BasePart")) {
			this.rocketSpawnPoint = spawnPoint;
		} else {
			warn(`Room ${this.name}: ${MOVABLE_MODEL} missing ${ROCKET_SPAWN_POINT} — no rocket will be placed`);
		}

		// Billboard is optional — gameplay still works without it.
		const billboard = buttonModel.FindFirstChild(UI_PART)?.FindFirstChild(BILLBOARD);
		if (billboard?.IsA("BillboardGui")) {
			this.billboardGui = billboard;
			const label = billboard.FindFirstChild(GAIN_LABEL, true);
			if (label?.IsA("TextLabel")) this.gainLabel = label;
		}

		// Optional spawn marker, placed anywhere in the room folder. Matched by name
		// (any of SPAWN_PART_NAMES) so a regular Part works.
		for (const partName of SPAWN_PART_NAMES) {
			const part = folder.FindFirstChild(partName, true);
			if (part?.IsA("BasePart")) {
				this.spawnPart = part;
				break;
			}
		}
		if (!this.spawnPart) {
			warn(`Room ${this.name}: no spawn part (${SPAWN_PART_NAMES.join("/")}) — players won't spawn here`);
		}

		// Optional owner-display model. We resolve the name label here, and disable
		// the "your base" BillboardGui on the server so it stays hidden until each
		// client locally enables it on their own room (OwnerIndicatorController).
		const ownerDisplay = folder.FindFirstChild(OWNER_DISPLAY);
		if (ownerDisplay) {
			const nameLabel = ownerDisplay.FindFirstChild(NAME_TEXT_LABEL, true);
			if (nameLabel?.IsA("TextLabel")) {
				this.ownerNameLabel = nameLabel;
				this.ownerNameLabel.Text = EMPTY_BASE_TEXT;
			} else {
				warn(`Room ${this.name}: ${OWNER_DISPLAY} missing TextLabel "${NAME_TEXT_LABEL}"`);
			}

			const indicatorPart = ownerDisplay.FindFirstChild(OWNER_INDICATOR_PART);
			const billboard = indicatorPart?.FindFirstChildOfClass("BillboardGui");
			if (billboard) billboard.Enabled = false;
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

	// Mark the room as owned by `player`. Prompt visibility is handled client-side
	// (RoomPromptController) off the player's AssignedRoom attribute.
	assign(player: Player): void {
		this.occupant = player;
		if (this.ownerNameLabel) this.ownerNameLabel.Text = `Base of ${player.DisplayName}`;
	}

	// Free the room and reset the billboard to "Empty".
	release(): void {
		this.occupant = undefined;
		this.proximityPrompt.ObjectText = EMPTY_TEXT;
		if (this.gainLabel) this.gainLabel.Text = EMPTY_TEXT;
		if (this.ownerNameLabel) this.ownerNameLabel.Text = EMPTY_BASE_TEXT;
	}

	// Display the occupant's BaseCash on the billboard + proximity prompt.
	setGainCash(cash: number): void {
		// Billboard label prefixed with '$' (gain cash is always positive).
		if (this.gainLabel) this.gainLabel.Text = `$${FormatCash(cash)}`;
		this.proximityPrompt.ObjectText = `${FormatCash(cash)} money`;
	}
}
