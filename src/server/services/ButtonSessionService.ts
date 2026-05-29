export interface ButtonSession {
	baseCash: number;
	proximityPrompt: ProximityPrompt;
	billboardGui?: BillboardGui;
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

	// Re-enable the proximity prompt, unanchor the player, restore the
	// label-billboard for this player, and clear the session.
	cleanup(player: Player): void {
		const session = sessions.get(player);
		if (session) {
			session.proximityPrompt.Enabled = true;
			// PlayerToHideFrom was set to this player on trigger — clear it so
			// the billboard becomes visible to them again.
			if (session.billboardGui && session.billboardGui.PlayerToHideFrom === player) {
				session.billboardGui.PlayerToHideFrom = undefined;
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
