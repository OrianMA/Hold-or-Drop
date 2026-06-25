import { Players, Workspace } from "@rbxts/services";

// Per-player visibility for the "join the community for ×2" prompts.
//
// Every room folder has a CommunityJoinPart holding a ProximityPrompt + a
// BillboardGui, both globally Enabled in Studio (no per-player server toggle).
// This controller narrows that down on each client, off two replicated player
// attributes — exactly like RoomPromptController / OwnerIndicatorController, and
// since client-side Enabled writes don't replicate, each player only affects
// their own view:
//
//   • AssignedRoom — the P{n} folder this player owns. The CommunityJoinPart is
//     shown ONLY on the owned room; every other room's prompt + billboard are
//     disabled (no point nagging a player at someone else's button).
//   • InCommunity  — true once the player is a member of the community group, so
//     the ×2 is already applied server-side (BoostService). On the owned room we
//     then DISABLE the prompt (nothing left to join) and flip the billboard text
//     to the "claimed" badge instead of hiding it.
//
// Roblox exposes no in-experience "join group/community" API, so the prompt can't
// open a join dialog — it just re-checks membership server-side (RoomService →
// BoostService.refreshCommunity) and the player joins via Roblox's own UI.

const PLAYER_ZONES = "PlayerZones";
const COMMUNITY_JOIN_PART = "CommunityJoinPart";
const IN_COMMUNITY_ATTR = "InCommunity";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";
// Billboard text once the player is a member (reward already granted).
const CLAIMED_TEXT = "x2 réclamé";

interface JoinEntry {
	roomName: string;
	prompt?: ProximityPrompt;
	billboard?: BillboardGui;
	label?: TextLabel;
	// The Studio-authored CTA text, captured once so we can restore it (the
	// "claimed" swap is reversible and we don't hardcode the join wording here).
	defaultText: string;
}

export function init(): void {
	const player = Players.LocalPlayer;

	const entries: JoinEntry[] = [];

	const evaluate = (): void => {
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		const member = player.GetAttribute(IN_COMMUNITY_ATTR) === true;

		for (const entry of entries) {
			const own = entry.roomName === assigned;
			// Prompt: only on our own room, and only while we still need to join.
			if (entry.prompt) entry.prompt.Enabled = own && !member;
			// Billboard: only on our own room — hidden on every other room.
			if (entry.billboard) entry.billboard.Enabled = own;
			// Text: claimed badge once we're a member, else the authored CTA.
			if (entry.label) entry.label.Text = member ? CLAIMED_TEXT : entry.defaultText;
		}
	};

	// Server-driven — re-render whenever ownership or membership changes (e.g. the
	// player joins the group then triggers the prompt and the server re-checks).
	player.GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR).Connect(evaluate);
	player.GetAttributeChangedSignal(IN_COMMUNITY_ATTR).Connect(evaluate);

	// Discovery runs off the main thread (WaitForChild may yield while the zones
	// stream/replicate in).
	task.spawn(() => {
		const zones = Workspace.WaitForChild(PLAYER_ZONES, 30);
		if (!zones) {
			warn("CommunityJoinController: Workspace/PlayerZones not found");
			return;
		}

		const register = (folder: Instance): void => {
			const part = folder.FindFirstChild(COMMUNITY_JOIN_PART);
			if (!part) return; // not every room necessarily has one
			const prompt = part.FindFirstChildOfClass("ProximityPrompt");
			const billboard = part.FindFirstChildOfClass("BillboardGui");
			const label = billboard?.FindFirstChildOfClass("TextLabel");
			entries.push({
				roomName: folder.Name,
				prompt,
				billboard,
				label,
				defaultText: label ? label.Text : "",
			});
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
