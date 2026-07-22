import { Players, TweenService, Workspace } from "@rbxts/services";

const DEFAULT_DURATION = 0.35;
const camera = Workspace.CurrentCamera!;

// Zoom distances (studs from the camera subject) snapped on each transition:
// dezoomed to frame the rocket + a bit of the room when the camera goes to the
// rocket, and back to the Roblox default when it returns to the player.
const ROCKET_VIEW_DISTANCE = 35;
const DEFAULT_VIEW_DISTANCE = 12.5;
// How long the zoom stays locked at the snapped distance before the player regains
// free zoom control (one snap, then released).
const ZOOM_SNAP_HOLD = 0.1;

let previousCameraType: Enum.CameraType | undefined;

// ── Rocket follow camera ───────────────────────────────────────────────────────
// During the button/rocket flow the camera uses the default Roblox camera
// (CameraType.Custom) with its CameraSubject pointed at the rocket pivot
// (CameraParentPart) instead of the player. The player keeps native camera
// controls (rotate/zoom), and because the MovableModel carries CameraParentPart
// up with it, the camera follows the rocket as it climbs with no extra code.

// The default Roblox camera subject (the player's Humanoid) so we can hand the
// camera back to the player after the rocket flow.
function playerCameraSubject(): Humanoid | BasePart | undefined {
	const character = Players.LocalPlayer.Character;
	const humanoid = character?.FindFirstChildOfClass("Humanoid");
	if (humanoid) return humanoid;
	const hrp = character?.FindFirstChild("HumanoidRootPart");
	return hrp?.IsA("BasePart") ? hrp : undefined;
}

// Snap the default Roblox camera to a fixed zoom distance, then release the lock so
// the player keeps free zoom control. Pinning Min == Max forces the distance; the
// PlayerModule eases into it (no hard pop). Restored next tick to the captured limits.
function snapZoomDistance(distance: number): void {
	const player = Players.LocalPlayer;
	const prevMin = player.CameraMinZoomDistance;
	const prevMax = player.CameraMaxZoomDistance;
	player.CameraMinZoomDistance = distance;
	player.CameraMaxZoomDistance = distance;
	task.delay(ZOOM_SNAP_HOLD, () => {
		player.CameraMinZoomDistance = prevMin;
		player.CameraMaxZoomDistance = prevMax;
	});
}

export namespace CameraController {
	export function SetCinematic() {
		camera.CameraType = Enum.CameraType.Scriptable;
	}

	export function AnimateTo(targetCFrame: CFrame, duration = DEFAULT_DURATION) {
		const tween = TweenService.Create(
			camera,
			new TweenInfo(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame: targetCFrame },
		);

		tween.Play();
		tween.Completed.Wait();
	}

	// Point the default Roblox camera at the rocket: native controls, but the camera
	// follows subjectPart (CameraParentPart) so it tracks the rocket as it climbs.
	// posCFrame is unused now that the native camera owns positioning — kept so the
	// call site (ButtonMenuBehavior) stays unchanged.
	export function StartOrbit(_posCFrame: CFrame, subjectPart: BasePart) {
		StopOrbit();
		camera.CameraType = Enum.CameraType.Custom;
		camera.CameraSubject = subjectPart;
		// Pull back so the player sees the rocket plus a bit of the room before launch.
		snapZoomDistance(ROCKET_VIEW_DISTANCE);
	}

	export function StopOrbit() {
		// Native rocket-follow has no render loop/connections to tear down; the camera
		// subject is restored by BringBackPlayerCamera. Kept so call sites are unchanged.
	}

	export function BringBackPlayerCamera(duration = DEFAULT_DURATION) {
		// From a Scriptable cinematic (loss) tween smoothly back to the player;
		// from the native rocket-follow there's nothing to tween — handing the subject
		// back to the player is the native return.
		if (camera.CameraType === Enum.CameraType.Scriptable) {
			AnimateTo(Players.LocalPlayer.Character?.GetPivot()!, duration);
		}
		StopOrbit();
		const subject = playerCameraSubject();
		if (subject) camera.CameraSubject = subject;
		camera.CameraType = previousCameraType ?? Enum.CameraType.Custom;
		// Classic reset: snap the zoom back to the default distance behind the player
		// (the rocket view left the camera dezoomed).
		snapZoomDistance(DEFAULT_VIEW_DISTANCE);
	}
}
