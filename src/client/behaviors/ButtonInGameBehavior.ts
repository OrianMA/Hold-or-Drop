import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";
import { UserInputService } from "@rbxts/services";

// Called once at startup — registers all game-state event listeners
export function init(): void {
	Events.MultiplierUpdateEvent.OnClientEvent.Connect((multiplier: number) => {
		// TODO: update multiplier label in ButtonInGame UI
		print(`Multiplier: ${multiplier}x`);
	});

	Events.RiskUpdateEvent.OnClientEvent.Connect((risk: number) => {
		// TODO: update risk indicator in ButtonInGame UI (risk is 0–1)
		print(`Risk: ${math.round(risk * 100)}%`);
	});

	Events.ButtonExplodedEvent.OnClientEvent.Connect(() => {
		// TODO: screenshake, stress effect, explosion sound/particles
		print("Button exploded!");
	});

	Events.GameResultEvent.OnClientEvent.Connect((exploded: boolean, cashEarned: number, multiplier: number) => {
		CameraController.BringBackPlayerCamera();
		// TODO: show result popup (cash earned, whether it exploded)
		print(`Game over — exploded: ${exploded} | cash: ${cashEarned} | ${multiplier}x`);
	});
}

// Called each time the player starts a new game (after clicking StartButton)
export function setup(mainUI: ScreenGui): void {
	const buttonInGame = mainUI.WaitForChild("ButtonInGame") as Frame;
	const releaseButton = buttonInGame.WaitForChild("ReleaseButton") as TextButton;

	let released = false;

	const fireRelease = () => {
		if (released) return;
		released = true;
		spaceConn.Disconnect();
		Events.ReleaseButtonEvent.FireServer();
	};

	releaseButton.Activated.Connect(fireRelease);

	const spaceConn = UserInputService.InputBegan.Connect((input, gameProcessed) => {
		if (gameProcessed) return;
		if (input.KeyCode === Enum.KeyCode.Space) fireRelease();
	});
}
