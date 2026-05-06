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
};
