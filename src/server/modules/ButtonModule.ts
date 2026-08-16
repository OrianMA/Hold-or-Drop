import { UiService } from "server/services/UiService";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { Room } from "server/rooms/Room";
import { Events } from "shared/Event";
import { PopupType } from "shared/PopupType";

// Gameplay entry point for a single room's button. One instance per Room,
// created at startup. The billboard / prompt text and the enabled state are
// driven by the room itself (RoomService); this module only handles the trigger
// and hands off to the in-game flow.
//
// Access rule: a trigger is only honored when it comes from the room's current
// occupant — every button is reachable on foot, so non-owners are ignored.
export class ButtonModule {
	constructor(private readonly room: Room) {}

	bind(): void {
		this.room.proximityPrompt.Triggered.Connect((player) => this.onTriggered(player));
	}

	private onTriggered(player: Player): void {
		if (!this.room.owns(player)) return; // not your button
		// The prompt is hidden client-side during a session via the InSession
		// attribute, but that lags one replication round-trip — guard against a
		// double trigger here so we never start two sessions.
		if (ButtonSessionService.getSession(player)) return;

		const character = player.Character;
		if (!character) return;

		ButtonSessionService.setSession(player, { room: this.room });
		// Drives this player's client to hide their prompt while playing
		// (RoomPromptController); cleared in ButtonSessionService.cleanup().
		player.SetAttribute("InSession", true);

		// Hide the floating label-billboard for the active player only — restored
		// when ButtonSessionService.cleanup() runs at the end of the session.
		if (this.room.billboardGui) this.room.billboardGui.PlayerToHideFrom = player;

		Events.ButtonTriggerEvent.FireClient(player, this.room.cameraPosPart, this.room.cameraPivotPart);

		this.teleportPlayer(character);

		UiService.Show(player, PopupType.ButtonMenu);
	}

	private teleportPlayer(character: Model): void {
		const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
		if (!hrp) return;

		const playerSize = character.GetExtentsSize().Y;
		hrp.CFrame = this.room.playerPosPart.CFrame.add(new Vector3(0, playerSize / 2, 0));
		hrp.Anchored = true;
	}
}
