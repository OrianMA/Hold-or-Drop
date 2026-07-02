import { Players } from "@rbxts/services";
import { Events } from "shared/Event";

// Coordinates cancellation of in-flight "flying cash" floating texts — the end-game
// payout chunks (EndGameAnimation) and the loss-reward text (LossRewardBehavior).
//
// On a NORMAL rebirth the money balance is reset to 0 server-side; any floating text
// still flying toward the money HUD would otherwise land AFTER the reset and add money
// visually (and, without the server guard, actually). RebirthResetEvent tells us to
// drop them all: we destroy the in-flight frames and bump a generation counter so any
// deferred arrival callback that survives the destroy no-ops instead of banking.
//
// Each animation captures current() when it starts and checks isStale() before banking.

// Frame names used by the two spawn sites (EndGameAnimation + LossRewardBehavior).
const FLOATING_FRAME_NAMES = ["EndGameFloatingChunk", "EndGameBaseCashFly", "LossRewardFloatingText"];

let generation = 0;

function getInGameUI(): ScreenGui | undefined {
	const playerGui = Players.LocalPlayer.FindFirstChildOfClass("PlayerGui");
	const found = playerGui?.FindFirstChild("InGameUI");
	return found?.IsA("ScreenGui") ? found : undefined;
}

function cancelAll(): void {
	generation += 1; // invalidates every run that captured the previous value
	const screenGui = getInGameUI();
	if (!screenGui) return;
	for (const desc of screenGui.GetDescendants()) {
		if (FLOATING_FRAME_NAMES.includes(desc.Name)) desc.Destroy();
	}
}

export const FloatingCash = {
	// The generation an animation captures when it starts.
	current(): number {
		return generation;
	},

	// True once a rebirth has cancelled the run this generation belongs to.
	isStale(gen: number): boolean {
		return gen !== generation;
	},

	init(): void {
		Events.RebirthResetEvent.OnClientEvent.Connect(() => cancelAll());
	},
};
