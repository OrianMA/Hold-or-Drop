import { Players, Workspace } from "@rbxts/services";

// Per-player visibility for the "join the community for ×2" prompts.
//
// Every room folder has a CommunityJoinPart holding a ProximityPrompt + a
// BillboardGui, both globally Enabled in Studio (so every player sees them by
// default). Once a player is a member of the community group, the ×2 money boost is
// already applied server-side (BoostService → InCommunity attribute) and there's no
// reason to keep nagging them — so this controller hides BOTH the prompt and the
// billboard for members.
//
// InCommunity is resolved server-side and replicates as a player attribute: at join
// (BoostService.resolve, so an already-member is handled on spawn) and again when the
// player triggers the prompt (RoomService → BoostService.refreshCommunity). This
// controller just mirrors it. Enabled is a global property and client-side writes
// don't replicate (same trick as RoomPromptController), so hiding here only affects
// the local member — non-members still see the prompts.

const PLAYER_ZONES = "PlayerZones";
const COMMUNITY_JOIN_PART = "CommunityJoinPart";
const IN_COMMUNITY_ATTR = "InCommunity";

export function init(): void {
	const player = Players.LocalPlayer;

	const prompts: ProximityPrompt[] = [];
	const billboards: BillboardGui[] = [];

	const evaluate = (): void => {
		const member = player.GetAttribute(IN_COMMUNITY_ATTR) === true;
		for (const prompt of prompts) prompt.Enabled = !member;
		for (const billboard of billboards) billboard.Enabled = !member;
	};

	// Server-driven — re-render whenever membership changes (e.g. the player joins
	// the group then triggers the prompt and the server re-checks).
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
			if (prompt) prompts.push(prompt);
			if (billboard) billboards.push(billboard);
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
