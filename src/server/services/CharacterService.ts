import { Players } from "@rbxts/services";

const SCALE = {
	HeightScale: 1,
	WidthScale: 1,
	DepthScale: 1,
	HeadScale: 1,
};

function normalizeSize(player: Player, character: Model): void {
	const humanoid = character.FindFirstChildOfClass("Humanoid");
	if (!humanoid) return;

	const desc = Players.GetHumanoidDescriptionFromUserId(player.UserId);
	desc.HeightScale = SCALE.HeightScale;
	desc.WidthScale = SCALE.WidthScale;
	desc.DepthScale = SCALE.DepthScale;
	desc.HeadScale = SCALE.HeadScale;
	humanoid.ApplyDescription(desc);
}

export const CharacterService = {
	init(): void {
		Players.PlayerAdded.Connect((player) => {
			player.CharacterAdded.Connect((character) => normalizeSize(player, character));
		});

		// Handle players already in-game (e.g. during Studio testing)
		for (const player of Players.GetPlayers()) {
			player.CharacterAdded.Connect((character) => normalizeSize(player, character));
			if (player.Character) normalizeSize(player, player.Character);
		}
	},
};
