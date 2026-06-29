// Shared snapshot of the in-game multiplier label's last "peak" appearance.
// Captured by RocketLaunchBehavior on every MultiplierUpdate, consumed by
// EndGameAnimation so the ButtonFinishGame popup opens with a MultiplierText
// matching the size + color the player was looking at when the game ended.

export interface MultiplierVisualSnapshot {
	size: number;
	color: Color3;
}

let last: MultiplierVisualSnapshot | undefined;

export const MultiplierVisuals = {
	capture(size: number, color: Color3): void {
		last = { size, color };
	},

	getLast(): MultiplierVisualSnapshot | undefined {
		return last;
	},

	clear(): void {
		last = undefined;
	},
};
