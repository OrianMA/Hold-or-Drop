import { GroupService, Players, Workspace } from "@rbxts/services";
import { COMMUNITY } from "shared/ShopBalance";
import { Events } from "shared/Event";

// Per-player visibility + native join flow for the "join the community for ×2" prompts.
//
// Every room folder has a CommunityJoinPart (a visible Part) holding a
// ProximityPrompt + a BillboardGui, all globally Enabled in Studio (no per-player
// server toggle). This controller narrows that down on each client, off two
// replicated player attributes — exactly like RoomPromptController /
// OwnerIndicatorController, and since client-side writes don't replicate, each
// player only affects their own view:
//
//   • AssignedRoom — the P{n} folder this player owns. The CommunityJoinPart (the
//     part itself, its prompt and its billboard) is shown ONLY on the owned room;
//     every other room's part is made fully transparent and its prompt/billboard
//     disabled, so you only ever see the join cue at your own button.
//   • InCommunity  — true once the player is a member of the community group, so
//     the ×2 is already applied server-side (BoostService). On the owned room we
//     then DISABLE the prompt (nothing left to join) and flip the billboard text
//     to the "claimed" badge instead of hiding it.
//
// StreamingEnabled is ON, so a room's CommunityJoinPart can stream IN at any time
// (when the player gets near) and OUT again. We therefore (re)register per folder
// on ChildAdded — not a one-shot FindFirstChild at boot — and re-apply visibility
// each time a part appears, so a freshly streamed-in part is hidden immediately.
//
// Joining: triggering the owned room's prompt opens Roblox's NATIVE community-join
// card via GroupService:PromptJoinAsync (client-only). On a Joined/AlreadyMember
// result we fire CommunityJoinedEvent so the server re-checks membership (fresh,
// via GetGroupsAsync) and grants the ×2 — see BoostService.refreshCommunity.

const PLAYER_ZONES = "PlayerZones";
const COMMUNITY_JOIN_PART = "CommunityJoinPart";
const PROMPT_NAME = "ProximityPrompt";
const BILLBOARD_NAME = "BillboardGui";
const IN_COMMUNITY_ATTR = "InCommunity";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";
// Billboard text once the player is a member (reward already granted).
const CLAIMED_TEXT = "x2 réclamé";

interface JoinEntry {
	roomName: string;
	part: BasePart;
	prompt?: ProximityPrompt;
	billboard?: BillboardGui;
	label?: TextLabel;
	// The Studio-authored CTA text, captured once so we can restore it (the
	// "claimed" swap is reversible and we don't hardcode the join wording here).
	defaultText: string;
	// The part's Studio transparency, captured so hiding other rooms is reversible.
	defaultTransparency: number;
}

export function init(): void {
	const player = Players.LocalPlayer;

	// Keyed by room name so a part that streams out then back in (a fresh instance)
	// simply replaces the stale entry.
	const entries = new Map<string, JoinEntry>();

	const applyEntry = (entry: JoinEntry): void => {
		if (entry.part.Parent === undefined) return; // streamed out — skip
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		const member = player.GetAttribute(IN_COMMUNITY_ATTR) === true;
		const own = entry.roomName === assigned;
		// Part: visible only on our own room — fully transparent on every other.
		entry.part.Transparency = own ? entry.defaultTransparency : 1;
		// Prompt: only on our own room, and only while we still need to join.
		if (entry.prompt) entry.prompt.Enabled = own && !member;
		// Billboard: only on our own room — hidden on every other room.
		if (entry.billboard) entry.billboard.Enabled = own;
		// Text: claimed badge once we're a member, else the authored CTA.
		if (entry.label) entry.label.Text = member ? CLAIMED_TEXT : entry.defaultText;
	};

	const evaluate = (): void => {
		for (const [, entry] of entries) applyEntry(entry);
	};

	// Open Roblox's native community-join card, then tell the server to grant the
	// ×2 if the player joined. Runs off the main thread (PromptJoinAsync yields).
	const promptJoin = (): void => {
		// Re-guard: only meaningful on our own room while not yet a member.
		const assigned = (player.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		if (assigned === "") return;
		if (player.GetAttribute(IN_COMMUNITY_ATTR) === true) return;

		task.spawn(() => {
			const [ok, status] = pcall(() => GroupService.PromptJoinAsync(COMMUNITY.groupId));
			if (!ok) return;
			if (
				status === Enum.GroupMembershipStatus.Joined ||
				status === Enum.GroupMembershipStatus.AlreadyMember
			) {
				Events.CommunityJoinedEvent.FireServer();
			}
		});
	};

	// Register (or refresh) a room's CommunityJoinPart and apply visibility now.
	// Spawned because WaitForChild may yield while the prompt/billboard stream in.
	const registerPart = (roomName: string, part: Instance): void => {
		if (!part.IsA("BasePart")) return;
		task.spawn(() => {
			const promptInst = part.WaitForChild(PROMPT_NAME, 5);
			const billboardInst = part.WaitForChild(BILLBOARD_NAME, 5);
			const prompt = promptInst?.IsA("ProximityPrompt") ? promptInst : undefined;
			const billboard = billboardInst?.IsA("BillboardGui") ? billboardInst : undefined;
			const label = billboard?.FindFirstChildOfClass("TextLabel");
			const entry: JoinEntry = {
				roomName,
				part,
				prompt,
				billboard,
				label,
				defaultText: label ? label.Text : "",
				defaultTransparency: part.Transparency,
			};
			entries.set(roomName, entry);
			applyEntry(entry);

			// Triggering the prompt opens the native join card (client-only API).
			if (prompt) prompt.Triggered.Connect(promptJoin);
		});
	};

	// Watch one room folder: register the part if present, and again whenever one
	// streams in (StreamingEnabled re-adds it as a fresh instance).
	const watchFolder = (folder: Instance): void => {
		const existing = folder.FindFirstChild(COMMUNITY_JOIN_PART);
		if (existing) registerPart(folder.Name, existing);
		folder.ChildAdded.Connect((child) => {
			if (child.Name === COMMUNITY_JOIN_PART) registerPart(folder.Name, child);
		});
	};

	// Server-driven — re-render whenever ownership or membership changes (e.g. the
	// player joins the community via the card and the server grants the ×2).
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

		for (const folder of zones.GetChildren()) watchFolder(folder);

		// Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded.Connect((folder) => watchFolder(folder));
	});
}
