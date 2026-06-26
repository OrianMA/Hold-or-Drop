import { TweenService, Workspace } from "@rbxts/services";

// Cosmetic idle animation for the community mascot: every room's
// CommunityJoinPart holds a GrorianStudioMascot MeshPart that should gently float
// up and down. 100 % client / presentation — no server logic, like the other
// per-room visual controllers.
//
// StreamingEnabled is ON, so a mascot can stream IN at any time (a fresh instance)
// and OUT again. We therefore discover via WaitForChild / ChildAdded down the
// PlayerZones → P{n} → CommunityJoinPart → GrorianStudioMascot chain — never a
// one-shot FindFirstChild at boot — and (re)start the float each time a mascot
// appears. The MeshPart is anchored in Studio, so a local Position tween renders
// cleanly without fighting physics (client-only, never replicated).

const PLAYER_ZONES = "PlayerZones";
const COMMUNITY_JOIN_PART = "CommunityJoinPart";
const MASCOT_NAME = "GrorianStudioMascot";

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

// Watch one CommunityJoinPart for its mascot (present now or streamed in later).
function watchJoinPart(joinPart: Instance): void {
	const existing = joinPart.FindFirstChild(MASCOT_NAME);
	if (existing && existing.IsA("BasePart")) startFloat(existing);
	joinPart.ChildAdded.Connect((child) => {
		if (child.Name === MASCOT_NAME && child.IsA("BasePart")) startFloat(child);
	});
}

// Watch one room folder for its CommunityJoinPart (present now or streamed in later).
function watchFolder(folder: Instance): void {
	const existing = folder.FindFirstChild(COMMUNITY_JOIN_PART);
	if (existing) watchJoinPart(existing);
	folder.ChildAdded.Connect((child) => {
		if (child.Name === COMMUNITY_JOIN_PART) watchJoinPart(child);
	});
}

export function init(): void {
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
