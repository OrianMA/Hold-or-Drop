import { Players, Workspace } from "@rbxts/services";

// Per-player ProximityPrompt visibility.
//
// ProximityPrompt.Enabled is a global property, so the server can't show a prompt
// to one player only. Instead the server keeps every room's prompt disabled and
// publishes two attributes on each player:
//   • AssignedRoom — the P{n} folder name this player owns ("" when none)
//   • InSession    — true while the player is mid-button-game
//
// This controller (one per client) enables ONLY the local player's room prompts
// — the button prompt AND the rocket prompt, which both trigger the same game —
// and only when they're not already in a session. Client-side writes to Enabled
// don't replicate, so each player sees just their own prompts. The server still
// validates ownership on Triggered, so this is purely visibility/UX.

const PLAYER_ZONES = "PlayerZones";
const BUTTON_MODEL = "ButtonModel";
const BUTTON_PART = "ButtonPart";
// The rocket prompt lives on MovableModel/RocketProximityPromptPart (same prompt
// name) and is shown/hidden together with the button prompt.
const MOVABLE_MODEL = "MovableModel";
const ROCKET_PROMPT_PART = "RocketProximityPromptPart";
const PROMPT_NAME = "ProximityPrompt";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";
const IN_SESSION_ATTR = "InSession";

export function init(): void {
	const player = Players.LocalPlayer;

	// roomName ("P1") → its prompts (button + rocket), shown/hidden together
	const prompts = new Map<string, ProximityPrompt[]>();

	const evaluate = (): void => {
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		const inSession = player.GetAttribute(IN_SESSION_ATTR) === true;
		for (const [name, list] of prompts) {
			const enabled = name === assigned && !inSession;
			for (const prompt of list) prompt.Enabled = enabled;
		}
	};

	// Server-driven state — re-render whenever ownership or session state changes.
	player.GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR).Connect(evaluate);
	player.GetAttributeChangedSignal(IN_SESSION_ATTR).Connect(evaluate);

	// Discovery runs off the main thread (WaitForChild may yield while the zones
	// stream/replicate in).
	task.spawn(() => {
		const zones = Workspace.WaitForChild(PLAYER_ZONES, 30);
		if (!zones) {
			warn("RoomPromptController: Workspace/PlayerZones not found");
			return;
		}

		const register = (folder: Instance): void => {
			const list: ProximityPrompt[] = [];

			// Button prompt — ButtonModel/ButtonPart/ProximityPrompt
			const buttonModel = folder.WaitForChild(BUTTON_MODEL, 10);
			const buttonPart = buttonModel?.WaitForChild(BUTTON_PART, 10);
			const buttonPrompt = buttonPart?.WaitForChild(PROMPT_NAME, 10);
			if (buttonPrompt?.IsA("ProximityPrompt")) list.push(buttonPrompt);
			else warn(`RoomPromptController: no button ProximityPrompt under ${folder.Name}`);

			// Rocket prompt — MovableModel/RocketProximityPromptPart/ProximityPrompt
			const movableModel = folder.WaitForChild(MOVABLE_MODEL, 10);
			const rocketPart = movableModel?.WaitForChild(ROCKET_PROMPT_PART, 10);
			const rocketPrompt = rocketPart?.WaitForChild(PROMPT_NAME, 10);
			if (rocketPrompt?.IsA("ProximityPrompt")) list.push(rocketPrompt);
			else warn(`RoomPromptController: no rocket ProximityPrompt under ${folder.Name}`);

			if (list.size() > 0) prompts.set(folder.Name, list);
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
