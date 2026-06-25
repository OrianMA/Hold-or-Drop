import { Players } from "@rbxts/services";
import { Events } from "shared/Event";
import { PopupType } from "shared/PopupType";
import { UiService } from "server/services/UiService";
import { ButtonSessionService } from "server/services/ButtonSessionService";
import { PlayerDataService } from "server/services/PlayerDataService";

// EndGameButton gameplay state — entered when the player releases the button
// (success / parry / grace-period cancel) or when the player dies from the
// explosion. Coordinates the transition into the ButtonFinishGame popup.

export type EndGameMode = "released" | "killed";

const RELEASE_DELAY = 1; // 1s wait between release and the finish popup
const POST_RESPAWN_DELAY = 0.3; // small grace after respawn so UI doesn't pop in mid-load

// Credited to the player once the client signals the end of the last tween
// (EndGameFinishedEvent). One pending entry per player at most.
const pendingEarned = new Map<Player, number>();

function waitForRespawn(player: Player): void {
	const character = player.Character;
	const humanoid = character?.FindFirstChildOfClass("Humanoid");
	const alive = character !== undefined && humanoid !== undefined && humanoid.Health > 0;
	if (alive) return;
	player.CharacterAdded.Wait();
	task.wait(POST_RESPAWN_DELAY);
}

export const EndGameButtonModule = {
	// Called from ButtonInGameModule once an outcome is determined.
	// baseCash + multiplier drive the popup animation client-side; earned is the
	// amount we credit when the animation finishes. lossMultiplier (1 for wins,
	// LOOSE_WIN_MULTIPLIER for kills) is the factor applied to baseCash by the
	// client-side penalty animation before the multiplier drain.
	enter(
		player: Player,
		mode: EndGameMode,
		baseCash: number,
		multiplier: number,
		earned: number,
		lossMultiplier: number,
	): void {
		ButtonSessionService.cleanup(player);
		UiService.HideCurrent(player);

		pendingEarned.set(player, earned);

		task.spawn(() => {
			if (mode === "released") {
				task.wait(RELEASE_DELAY);
			} else {
				waitForRespawn(player);
			}

			// Player may have disconnected while we were waiting
			if (player.Parent === undefined) {
				pendingEarned.delete(player);
				return;
			}

			UiService.Show(player, PopupType.ButtonFinishGame);
			Events.EndGameStartEvent.FireClient(player, baseCash, multiplier, lossMultiplier);
		});
	},

	// Wired by services/index.ts so the popup hides once the client animation finishes
	init(): void {
		Events.EndGameFinishedEvent.OnServerEvent.Connect((player) => {
			const earned = pendingEarned.get(player) ?? 0;
			pendingEarned.delete(player);
			if (earned > 0) PlayerDataService.add(player, "Money", earned);
			UiService.Hide(player, PopupType.ButtonFinishGame);
		});

		Players.PlayerRemoving.Connect((player) => pendingEarned.delete(player));
	},
};
