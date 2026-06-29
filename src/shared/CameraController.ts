import { Players, RunService, TweenService, UserInputService, Workspace } from "@rbxts/services";

const DEFAULT_DURATION = 0.35;
const camera = Workspace.CurrentCamera!;

let previousCameraType: Enum.CameraType | undefined;

// ── Orbit camera ──────────────────────────────────────────────────────────────
// Dynamic camera used during the button/rocket flow: the player rotates freely
// (right-drag on PC, touch-drag on mobile) but the camera always looks at a pivot
// part (CameraParentPart). The pivot position is read live each frame, so moving
// the pivot (e.g. with the rocket) makes the camera follow automatically.
const ORBIT_BINDING = "HoldOrDropCameraOrbit";
const ORBIT_SENSITIVITY = 0.0075; // radians per pixel of drag
const MIN_PITCH = math.rad(-15);
const MAX_PITCH = math.rad(80);

let orbitPivot: BasePart | undefined;
let orbitYaw = 0;
let orbitPitch = 0;
let orbitRadius = 0;
let orbitConns: RBXScriptConnection[] = [];
let orbitDragging = false; // PC right-button held
let orbitTouch: InputObject | undefined; // active mobile drag touch

function orbitOffset(): Vector3 {
	const horizontal = orbitRadius * math.cos(orbitPitch);
	return new Vector3(horizontal * math.sin(orbitYaw), orbitRadius * math.sin(orbitPitch), horizontal * math.cos(orbitYaw));
}

function applyOrbitDelta(dx: number, dy: number): void {
	orbitYaw -= dx * ORBIT_SENSITIVITY;
	orbitPitch = math.clamp(orbitPitch - dy * ORBIT_SENSITIVITY, MIN_PITCH, MAX_PITCH);
}

function orbitStep(): void {
	if (!orbitPivot) return;
	const pivotPos = orbitPivot.Position;
	camera.CFrame = CFrame.lookAt(pivotPos.add(orbitOffset()), pivotPos);
}

function bindOrbitInput(): void {
	orbitConns.push(
		UserInputService.InputBegan.Connect((input, gameProcessed) => {
			if (gameProcessed) return;
			if (input.UserInputType === Enum.UserInputType.MouseButton2) {
				orbitDragging = true;
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition;
			} else if (input.UserInputType === Enum.UserInputType.Touch && orbitTouch === undefined) {
				orbitTouch = input;
			}
		}),
	);
	orbitConns.push(
		UserInputService.InputChanged.Connect((input) => {
			if (input.UserInputType === Enum.UserInputType.MouseMovement && orbitDragging) {
				applyOrbitDelta(input.Delta.X, input.Delta.Y);
			} else if (input.UserInputType === Enum.UserInputType.Touch && input === orbitTouch) {
				applyOrbitDelta(input.Delta.X, input.Delta.Y);
			}
		}),
	);
	orbitConns.push(
		UserInputService.InputEnded.Connect((input) => {
			if (input.UserInputType === Enum.UserInputType.MouseButton2) {
				orbitDragging = false;
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default;
			} else if (input === orbitTouch) {
				orbitTouch = undefined;
			}
		}),
	);
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

	// Smoothly move to the start pose (looking at the pivot from posCFrame), then
	// hand off to a live orbit the player can rotate. Always faces pivotPart.
	export function StartOrbit(posCFrame: CFrame, pivotPart: BasePart) {
		StopOrbit();
		camera.CameraType = Enum.CameraType.Scriptable;

		const pivotPos = pivotPart.Position;
		const delta = posCFrame.Position.sub(pivotPos);
		orbitRadius = delta.Magnitude;
		orbitPitch =
			orbitRadius > 0 ? math.clamp(math.asin(math.clamp(delta.Y / orbitRadius, -1, 1)), MIN_PITCH, MAX_PITCH) : 0;
		orbitYaw = math.atan2(delta.X, delta.Z);
		orbitPivot = pivotPart;

		// Entry transition to the seeded orbit pose (looking straight at the pivot),
		// then start the per-frame loop so the pose matches seamlessly.
		const startPos = pivotPos.add(orbitOffset());
		AnimateTo(CFrame.lookAt(startPos, pivotPos));

		RunService.BindToRenderStep(ORBIT_BINDING, Enum.RenderPriority.Camera.Value, orbitStep);
		bindOrbitInput();
	}

	export function StopOrbit() {
		if (orbitPivot === undefined && orbitConns.size() === 0) return; // not active
		pcall(() => RunService.UnbindFromRenderStep(ORBIT_BINDING));
		orbitConns.forEach((c) => c.Disconnect());
		orbitConns = [];
		if (orbitDragging) {
			orbitDragging = false;
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default;
		}
		orbitTouch = undefined;
		orbitPivot = undefined;
	}

	export function BringBackPlayerCamera(duration = DEFAULT_DURATION) {
		StopOrbit();
		AnimateTo(Players.LocalPlayer.Character?.GetPivot()!, duration);
		Reset();
	}

	function Reset() {
		camera.CameraType = previousCameraType ?? Enum.CameraType.Custom;
	}
}
