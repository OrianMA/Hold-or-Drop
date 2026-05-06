import { Events } from "shared/Event";
import { ButtonSession, ButtonSessionService } from "server/services/ButtonSessionService";
import { UiService } from "server/services/UiService";

interface MultiplierStage {
	multiplicatorAdded: number;
	duration: number;
}

const MULTIPLIER_STAGES: MultiplierStage[] = [
	{ multiplicatorAdded: 1, duration: 5 },
	{ multiplicatorAdded: 2, duration: 4 },
	{ multiplicatorAdded: 3, duration: 3 },
	{ multiplicatorAdded: 5, duration: 3 },
	{ multiplicatorAdded: 10, duration: 3 }, // last stage — runs forever
];

const MAX_RISK = 0.8;
const TICK_RATE = 0.5;
const LOOSE_WIN_MULTIPLIER = 0.3;

// Sum of all finite stage durations — defines the full length of the sine curve
let TOTAL_DURATION = 0;
for (const stage of MULTIPLIER_STAGES) {
	TOTAL_DURATION += stage.duration;
}

// EaseInQuad: risk starts near 0 and accelerates — reaches MAX_RISK at TOTAL_DURATION seconds
// After that, risk stays capped at MAX_RISK
function getRisk(timeHeld: number): number {
	const t = math.min(timeHeld / TOTAL_DURATION, 1);
	return MAX_RISK * (t * t);
}

// Single exit point for all outcomes: release, explosion, and quit from ButtonMenu
export function endButtonGame(player: Player): void {
	ButtonSessionService.cleanup(player);
	UiService.HideCurrent(player);
}

export function startButtonGame(player: Player, session: ButtonSession): void {
	const { baseCash } = session;
	let currentMultiplier = 1;
	let isActive = true;

	Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
	Events.RiskUpdateEvent.FireClient(player, 0);

	const releaseConn = Events.ReleaseButtonEvent.OnServerEvent.Connect((p) => {
		if (p !== player || !isActive) return;
		isActive = false;
		releaseConn.Disconnect();

		const earned = baseCash * currentMultiplier;
		Events.GameResultEvent.FireClient(player, false, earned, currentMultiplier);
		endButtonGame(player);
	});

	task.spawn(() => {
		const lastIndex = MULTIPLIER_STAGES.size() - 1;
		let stageIndex = 0;
		let timeHeld = 0; // total time elapsed across all stages

		while (isActive) {
			const stage = MULTIPLIER_STAGES[stageIndex];
			const isLastStage = stageIndex === lastIndex;

			let timeInStage = 0;
			let nextMultiplierTick = 1;
			let advanceStage = false;

			while (isActive) {
				task.wait(TICK_RATE);
				if (!isActive) break;

				timeInStage += TICK_RATE;
				timeHeld += TICK_RATE;

				// +multiplicatorAdded to the multiplier once per elapsed second
				while (timeInStage >= nextMultiplierTick) {
					currentMultiplier += stage.multiplicatorAdded;
					Events.MultiplierUpdateEvent.FireClient(player, currentMultiplier);
					nextMultiplierTick++;
				}

				// Risk follows a sine curve over the total stage duration
				const risk = getRisk(timeHeld);
				Events.RiskUpdateEvent.FireClient(player, risk);

				// Explosion check
				if (math.random() < risk) {
					isActive = false;
					releaseConn.Disconnect();

					const earned = math.floor(baseCash * currentMultiplier * LOOSE_WIN_MULTIPLIER);
					Events.ButtonExplodedEvent.FireClient(player);
					task.wait(0.5);
					Events.GameResultEvent.FireClient(player, true, earned, currentMultiplier);
					endButtonGame(player);
					return;
				}

				if (!isLastStage && timeInStage >= stage.duration) {
					advanceStage = true;
					break;
				}
			}

			if (!advanceStage) break;
			stageIndex++;
		}
	});
}
