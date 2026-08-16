import { Players, Workspace } from "@rbxts/services";

// Per-player ProximityPrompt visibility.
//
// ProximityPrompt.Enabled is a global property, so the server can't show a prompt
// to one player only. Instead the server keeps every room's prompt disabled and
// publishes two attributes on each player:
//   • AssignedRoom — the P{n} folder name this player owns ("" when none)
//   • InSession    — true while the player is mid-button-game
//
// This controller (one per client) enables ONLY the local player's room button
// prompt, and only when they're not already in a session. Client-side writes to
// Enabled don't replicate, so each player sees just their own prompt. The server
// still validates ownership on Triggered, so this is purely visibility/UX.

const PLAYER_ZONES = "PlayerZones";
const BUTTON_MODEL = "ButtonModel";
const BUTTON_PART = "ButtonPart";
const PROMPT_NAME = "ProximityPrompt";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";
const IN_SESSION_ATTR = "InSession";

export function init(): void {
	const player = Players.LocalPlayer;

	// roomName ("P1") → its button prompt
	const prompts = new Map<string, ProximityPrompt>();

	const evaluate = (): void => {
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		const inSession = player.GetAttribute(IN_SESSION_ATTR) === true;
		for (const [name, prompt] of prompts) {
			prompt.Enabled = name === assigned && !inSession;
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
			// Button prompt — ButtonModel/ButtonPart/ProximityPrompt
			const buttonModel = folder.WaitForChild(BUTTON_MODEL, 10);
			const buttonPart = buttonModel?.WaitForChild(BUTTON_PART, 10);
			const buttonPrompt = buttonPart?.WaitForChild(PROMPT_NAME, 10);
			if (buttonPrompt?.IsA("ProximityPrompt")) prompts.set(folder.Name, buttonPrompt);
			else warn(`RoomPromptController: no button ProximityPrompt under ${folder.Name}`);
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
