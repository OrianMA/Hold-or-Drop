import { Players, TweenService, Workspace } from "@rbxts/services";

const DEFAULT_DURATION = 0.35;
const camera = Workspace.CurrentCamera!;

let previousCameraType: Enum.CameraType | undefined;

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

	export function BringBackPlayerCamera(duration = DEFAULT_DURATION) {
		AnimateTo(Players.LocalPlayer.Character?.GetPivot()!, duration);
		Reset();
	}

	function AnimateTween() {}

	function Reset() {
		camera.CameraType = previousCameraType ?? Enum.CameraType.Custom;
	}
}
