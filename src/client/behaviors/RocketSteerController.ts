import { Players, RunService } from "@rbxts/services";
import { Events } from "shared/Event";

// Redirects the player's NATIVE left/right movement to the flying rocket. During a run
// the character is anchored (ButtonModule.teleportPlayer), so the movement input never
// walks it — we read the raw move vector from Roblox's own ControlModule, which reports
// input identically across keyboard (A/D), the mobile thumbstick and gamepad sticks,
// independent of the camera. Reusing the native controls means the feature works on
// every device with no extra UI.
//
// We quantise the horizontal axis to -1 (left) / 0 / +1 (right) and fire RocketSteerEvent
// only when it changes, so a whole flight costs a handful of RemoteEvent calls. The server
// (RocketLauncher.setSteer) does the actual, smooth, altitude-scaled rolling.

// Minimal shape of the ControlModule API we use (GetControls():GetMoveVector()).
interface Controls {
	GetMoveVector(this: Controls): Vector3;
}
interface PlayerModuleApi {
	GetControls(this: PlayerModuleApi): Controls;
}

// Ignore tiny thumbstick drift so a resting stick reads as "no steer".
const DEADZONE = 0.15;

let controls: Controls | undefined;
let enabled = false;
let lastSent = 0; // last direction fired to the server (avoids per-frame spam)
let pollConn: RBXScriptConnection | undefined;

// Roblox's ControlModule lives in the player's replicated PlayerModule. Require it once
// and cache the Controls object (native input, all devices).
function getControls(): Controls | undefined {
	if (controls) return controls;
	const playerScripts = Players.LocalPlayer.FindFirstChild("PlayerScripts");
	const moduleScript = playerScripts?.FindFirstChild("PlayerModule") as ModuleScript | undefined;
	if (!moduleScript) return undefined;
	const playerModule = require(moduleScript) as PlayerModuleApi;
	controls = playerModule.GetControls();
	return controls;
}

function poll(): void {
	if (!enabled) return;
	const c = getControls();
	if (!c) return;
	const x = c.GetMoveVector().X; // horizontal axis: -left / +right, camera-independent
	const dir = x > DEADZONE ? 1 : x < -DEADZONE ? -1 : 0;
	if (dir !== lastSent) {
		lastSent = dir;
		Events.RocketSteerEvent.FireServer(dir);
	}
}

export const RocketSteerController = {
	// Begin forwarding steering — called when a run starts (RocketLaunchBehavior.setup).
	start(): void {
		if (enabled) return;
		enabled = true;
		lastSent = 0;
		pollConn?.Disconnect();
		pollConn = RunService.RenderStepped.Connect(poll);
	},

	// Stop forwarding and release the rocket to neutral — called when the run ends.
	stop(): void {
		if (!enabled) return;
		enabled = false;
		pollConn?.Disconnect();
		pollConn = undefined;
		if (lastSent !== 0) {
			lastSent = 0;
			Events.RocketSteerEvent.FireServer(0);
		}
	},
};
