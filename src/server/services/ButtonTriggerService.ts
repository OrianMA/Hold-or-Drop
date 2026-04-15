export const ButtonTriggerService = {
	init() {
		const buttons = game.Workspace.FindFirstChild("Buttons") as Folder | undefined;
		if (!buttons) return;

		for (const buttonModel of buttons.GetChildren()) {
			const proximityPrompt = buttonModel
				.FindFirstChild("buttonPart")
				?.FindFirstChildOfClass("ProximityPrompt") as ProximityPrompt | undefined;
			const placeholder = buttonModel.FindFirstChild("PlayerPosPlaceHolder") as BasePart | undefined;

			if (!proximityPrompt || !placeholder) continue;

			proximityPrompt.Triggered.Connect((player) => {
				const character = player.Character;
				if (!character) return;

				const hrp = character.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
				if (!hrp) return;

				const playerSize = character.GetExtentsSize().Y;
				hrp.CFrame = placeholder.CFrame.add(new Vector3(0, playerSize / 2, 0));
				hrp.Anchored = true;
				proximityPrompt.Enabled = false;
			});
		}
	},
};
