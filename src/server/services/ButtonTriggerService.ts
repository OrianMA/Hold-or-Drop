import { ButtonModule } from "../modules/ButtonModule";

export const ButtonTriggerService = {
	init() {
		const buttons = game.Workspace.FindFirstChild("Buttons") as Folder | undefined;
		if (!buttons) return;

		for (const buttonModel of buttons.GetChildren()) {
			new ButtonModule().init(buttonModel);
		}
	},
};
