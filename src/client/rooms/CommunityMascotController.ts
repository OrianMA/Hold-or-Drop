import { Players, TweenService, Workspace } from "@rbxts/services";

// Community mascot, per room. The GrorianStudioMascot MeshPart sits directly in
// each room folder (PlayerZones/P{n}/GrorianStudioMascot) and does two things,
// 100 % client / presentation — no server logic:
//
//   • Idle float — a gentle up/down hover (looping Position tween). The MeshPart is
//     anchored in Studio, so a local tween renders cleanly without fighting physics.
//   • Per-player visibility — shown ONLY on the player's own room; on every other
//     room it is made fully transparent. Exactly the same rule the CommunityJoinPart
//     elements follow (see CommunityJoinController), driven by the replicated
//     AssignedRoom attribute. Client-local writes don't replicate, so each player
//     only affects their own view.
//
// StreamingEnabled is ON, so a mascot can stream IN at any time (a fresh instance)
// and OUT again. We therefore discover via WaitForChild / ChildAdded down the
// PlayerZones → P{n} → GrorianStudioMascot chain — never a one-shot FindFirstChild
// at boot — (re)start the float and (re)apply visibility each time a mascot appears.

const PLAYER_ZONES = "PlayerZones";
const MASCOT_NAME = "GrorianStudioMascot";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";

// How far (studs) the mascot rises from its resting position, and how long one
// rise (or fall) takes. Slow + smooth = a gentle hover.
const FLOAT_HEIGHT = 1;
const FLOAT_DURATION = 2;

const floatInfo = new TweenInfo(
	FLOAT_DURATION,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1, // repeat forever
	true, // reverse (rise then fall, back to the base position)
);

interface MascotEntry {
	roomName: string;
	mascot: BasePart;
	// The mascot's Studio transparency, captured so hiding other rooms is reversible.
	defaultTransparency: number;
}

// Start a looping float on one anchored mascot from its current resting position.
function startFloat(mascot: BasePart): void {
	const basePosition = mascot.Position;
	const tween = TweenService.Create(mascot, floatInfo, {
		Position: basePosition.add(new Vector3(0, FLOAT_HEIGHT, 0)),
	});
	// A small random phase so the mascots across rooms don't bob in lockstep.
	task.spawn(() => {
		task.wait(math.random() * FLOAT_DURATION);
		if (mascot.Parent !== undefined) tween.Play();
	});
}

export function init(): void {
	const player = Players.LocalPlayer;

	// Keyed by room name so a mascot that streams out then back in (a fresh
	// instance) simply replaces the stale entry.
	const entries = new Map<string, MascotEntry>();

	// Visible only on our own room — fully transparent on every other.
	const applyVisibility = (entry: MascotEntry): void => {
		if (entry.mascot.Parent === undefined) return; // streamed out — skip
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		const own = entry.roomName === assigned;
		entry.mascot.Transparency = own ? entry.defaultTransparency : 1;
	};

	const evaluate = (): void => {
		for (const [, entry] of entries) applyVisibility(entry);
	};

	// Register (or refresh) a room's mascot: start its float and apply visibility now.
	const registerMascot = (roomName: string, mascot: BasePart): void => {
		const entry: MascotEntry = {
			roomName,
			mascot,
			defaultTransparency: mascot.Transparency,
		};
		entries.set(roomName, entry);
		applyVisibility(entry);
		startFloat(mascot);
	};

	// Watch one room folder for its mascot (present now or streamed in later).
	const watchFolder = (folder: Instance): void => {
		const existing = folder.FindFirstChild(MASCOT_NAME);
		if (existing && existing.IsA("BasePart")) registerMascot(folder.Name, existing);
		folder.ChildAdded.Connect((child) => {
			if (child.Name === MASCOT_NAME && child.IsA("BasePart")) registerMascot(folder.Name, child);
		});
	};

	// Server-driven — re-render whenever ownership changes (room (re)assignment).
	player.GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR).Connect(evaluate);

	// Discovery runs off the main thread (WaitForChild may yield while the zones
	// stream / replicate in).
	task.spawn(() => {
		const zones = Workspace.WaitForChild(PLAYER_ZONES, 30);
		if (!zones) {
			warn("CommunityMascotController: Workspace/PlayerZones not found");
			return;
		}

		for (const folder of zones.GetChildren()) watchFolder(folder);

		// Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded.Connect((folder) => watchFolder(folder));
	});
}
