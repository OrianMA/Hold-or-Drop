import { Players, Workspace } from "@rbxts/services";

// Per-player "your base" BillboardGui visibility.
//
// Each room has an OwnerDisplay/OwnerIndicatorPart/BillboardGui that should
// only show for the room's owner. BillboardGui.Enabled is a global property, so
// the server keeps it disabled (see Room.ts) and each client locally enables
// only the indicator on their own room. Client writes to Enabled don't replicate,
// so other players never see it. Same pattern as RoomPromptController.

const PLAYER_ZONES = "PlayerZones";
const OWNER_DISPLAY = "OwnerDisplay";
const OWNER_INDICATOR_PART = "OwnerIndicatorPart";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";

export function init(): void {
	const player = Players.LocalPlayer;

	// roomName ("P1") → its owner-indicator BillboardGui
	const billboards = new Map<string, BillboardGui>();

	const evaluate = (): void => {
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		for (const [name, billboard] of billboards) {
			billboard.Enabled = name === assigned;
		}
	};

	player.GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR).Connect(evaluate);

	task.spawn(() => {
		const zones = Workspace.WaitForChild(PLAYER_ZONES, 30);
		if (!zones) {
			warn("OwnerIndicatorController: Workspace/PlayerZones not found");
			return;
		}

		const register = (folder: Instance): void => {
			const ownerDisplay = folder.WaitForChild(OWNER_DISPLAY, 10);
			const indicatorPart = ownerDisplay?.WaitForChild(OWNER_INDICATOR_PART, 10);
			const billboard = indicatorPart?.FindFirstChildOfClass("BillboardGui");
			if (billboard) {
				billboard.Enabled = false; // safe default until evaluate() runs
				billboards.set(folder.Name, billboard);
			} else {
				warn(
					`OwnerIndicatorController: no BillboardGui under ${folder.Name}/${OWNER_DISPLAY}/${OWNER_INDICATOR_PART}`,
				);
			}
		};

		for (const folder of zones.GetChildren()) register(folder);
		evaluate();

		// Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded.Connect((folder) =>
			task.spawn(() => {
				register(folder);
				evaluate();
			}),
		);
	});
}
