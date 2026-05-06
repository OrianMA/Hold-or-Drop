export interface ButtonSession {
	baseCash: number;
	proximityPrompt: ProximityPrompt;
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

	// Re-enable the proximity prompt, unanchor the player, and clear the session
	cleanup(player: Player): void {
		const session = sessions.get(player);
		if (session) {
			session.proximityPrompt.Enabled = true;
		}

		const character = player.Character;
		if (character) {
			const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
			if (hrp) hrp.Anchored = false;
		}

		sessions.delete(player);
	},
};
