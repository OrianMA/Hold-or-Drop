import { Room } from "server/rooms/Room";

export interface ButtonSession {
	room: Room;
}

const sessions = new Map<Player, ButtonSession>();

export const ButtonSessionService = {
	setSession(player: Player, session: ButtonSession): void {
		sessions.set(player, session);
	},

	getSession(player: Player): ButtonSession | undefined {
		return sessions.get(player);
	},

	clearSession(player: Player): void {
		sessions.delete(player);
	},

	// End the session: clear the InSession flag (the client re-enables the owner's
	// prompt), unanchor the player, restore the label-billboard, drop the session.
	cleanup(player: Player): void {
		const session = sessions.get(player);
		if (session) {
			const room = session.room;
			// PlayerToHideFrom was set to this player on trigger — clear it so the
			// billboard becomes visible to them again.
			if (room.billboardGui && room.billboardGui.PlayerToHideFrom === player) {
				room.billboardGui.PlayerToHideFrom = undefined;
			}
		}

		// Session over — the owner's client re-enables their prompt (RoomPromptController).
		player.SetAttribute("InSession", false);

		const character = player.Character;
		if (character) {
			const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
			if (hrp) hrp.Anchored = false;
		}

		sessions.delete(player);
	},
};
