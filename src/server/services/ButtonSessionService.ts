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

	// Re-enable the button, unanchor the player, restore the label-billboard for
	// this player, and clear the session.
	cleanup(player: Player): void {
		const session = sessions.get(player);
		if (session) {
			const room = session.room;
			// Only re-enable if the player still owns the room. If they left, the
			// room was already released (prompt disabled) — don't revive an empty
			// room's prompt.
			if (room.owns(player)) room.proximityPrompt.Enabled = true;
			// PlayerToHideFrom was set to this player on trigger — clear it so the
			// billboard becomes visible to them again.
			if (room.billboardGui && room.billboardGui.PlayerToHideFrom === player) {
				room.billboardGui.PlayerToHideFrom = undefined;
			}
		}

		const character = player.Character;
		if (character) {
			const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
			if (hrp) hrp.Anchored = false;
		}

		sessions.delete(player);
	},
};
