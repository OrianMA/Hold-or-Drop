import { Players, RunService } from "@rbxts/services";

// Character animations for the button game, played on the local player's rig.
//
// IMPORTANT: every id below MUST be owned by (or shared with) the experience's
// creator — the group 963505568. Otherwise Roblox refuses to load it and the
// track plays with Length 0 (nothing visible), logging:
//   "The experience doesn't have access permission to use asset id ..."
//
// An empty id is treated as "not provided yet" and simply does nothing, so the
// remaining animations can be filled in without breaking the others.
type AnimName = "interact" | "quit" | "hold" | "release" | "parry";

const ANIM_IDS: Record<AnimName, string> = {
	interact: "rbxassetid://123442755794873", // "hand on button": reach onto the button, then hold the last frame
	quit: "rbxassetid://93300469810162", // leaves the button before pressing: one-shot, chains out of `interact`
	hold: "rbxassetid://100517121510078", // "press button": press down, then hold the last frame for the whole game
	release: "rbxassetid://70993299432318", // releases the button: one-shot
	parry: "rbxassetid://84361846884673", // perfect-parry projection: one-shot
};

// Freeze a held pose this many seconds before the clip's natural end. Stopping
// just short keeps a non-looped track from auto-stopping (which blends back to
// the default idle), so it holds its final frame instead.
const FREEZE_EPSILON = 0.05;
// Give up trying to freeze if the asset never reports a Length (e.g. an id not
// owned by the group, see above) so the watcher can't spin forever.
const LOAD_TIMEOUT = 3;

// One AnimationTrack per name, lazily loaded against the current character's
// Animator. The cache is dropped when the character changes (respawn).
let loadedFor: Model | undefined;
const tracks = new Map<AnimName, AnimationTrack>();

// The held pose currently frozen on its last frame (interact/hold). One-shots
// (quit/release/parry) are fire-and-forget and intentionally not tracked here,
// so a later stop() — or the next held pose — never cuts them short.
let currentHold: AnimName | undefined;
// Heartbeat watcher that pins the held pose on its last frame, if active.
let freezeConn: RBXScriptConnection | undefined;

function getAnimator(): Animator | undefined {
	const character = Players.LocalPlayer.Character;
	const humanoid = character?.FindFirstChildOfClass("Humanoid");
	return humanoid?.FindFirstChildOfClass("Animator");
}

function getTrack(name: AnimName): AnimationTrack | undefined {
	const id = ANIM_IDS[name];
	if (id === "") return undefined; // id not provided yet — no-op

	const animator = getAnimator();
	if (!animator) return undefined;

	// Drop stale tracks if the character respawned since they were loaded.
	const character = animator.FindFirstAncestorOfClass("Model");
	if (character !== loadedFor) {
		tracks.clear();
		loadedFor = character;
	}

	let track = tracks.get(name);
	if (!track) {
		const anim = new Instance("Animation");
		anim.AnimationId = id;
		track = animator.LoadAnimation(anim);
		track.Priority = Enum.AnimationPriority.Action;
		tracks.set(name, track);
	}
	return track;
}

function cancelFreeze(): void {
	freezeConn?.Disconnect();
	freezeConn = undefined;
}

// Watch the playing track and pin it on its last frame (speed 0) so the pose
// holds. Self-cancels once frozen, when the pose is replaced, or if the asset
// never loads.
function freezeOnLastFrame(name: AnimName, track: AnimationTrack): void {
	cancelFreeze();
	const started = os.clock();
	freezeConn = RunService.Heartbeat.Connect(() => {
		if (currentHold !== name) {
			cancelFreeze(); // replaced / stopped
			return;
		}
		const length = track.Length;
		if (length === 0) {
			if (os.clock() - started > LOAD_TIMEOUT) cancelFreeze(); // never loaded
			return;
		}
		if (track.TimePosition >= length - FREEZE_EPSILON) {
			track.AdjustSpeed(0); // pin the last frame — the pose now holds
			cancelFreeze();
		}
	});
}

// Stop only the held pose (idempotent). Leaves one-shots untouched.
function stopHold(): void {
	cancelFreeze();
	if (currentHold === undefined) return;
	tracks.get(currentHold)?.Stop();
	currentHold = undefined;
}

// Stop everything we play (held pose + any in-flight one-shot) and hand the rig
// back to Roblox's default animations.
function stopAll(): void {
	cancelFreeze();
	currentHold = undefined;
	tracks.forEach((track) => track.Stop());
}

// Play a clip once, then hold its last frame until it's replaced or stopped.
function playHeld(name: AnimName): void {
	if (currentHold === name) return; // already holding this pose
	stopHold();
	const track = getTrack(name);
	if (!track) return;
	track.Looped = false;
	track.TimePosition = 0;
	track.Play(0.1, 1, 1); // fade in; speed 1 overrides a previously-frozen speed
	currentHold = name;
	freezeOnLastFrame(name, track);
}

// Play a clip once and let it blend back to the default Roblox animations at its
// natural end. Replaces any held pose; not tracked, so stop() can't cut it.
function playOnce(name: AnimName): void {
	stopHold(); // a one-shot replaces the held pose
	const track = getTrack(name);
	if (!track) return;
	track.Looped = false;
	track.TimePosition = 0;
	track.Play(0.1, 1, 1);
}

// Public API — called from the button behaviors at each gameplay transition.
export const ButtonAnimations = {
	playInteract: (): void => playHeld("interact"), // ButtonTriggerEvent (menu opens): reach & hold
	playQuit: (): void => playOnce("quit"), // Quit before pressing: chains out, then defaults
	playHold: (): void => playHeld("hold"), // game starts (setup): press & hold
	playRelease: (): void => playOnce("release"), // player releases: defaults at its end
	playParry: (): void => playOnce("parry"), // perfect parry: defaults on the finish popup
	stop: (): void => stopHold(), // death safety net: drop the held pose, leave one-shots alone
	restoreDefault: (): void => stopAll(), // finish popup opened: force back to default animations
};
