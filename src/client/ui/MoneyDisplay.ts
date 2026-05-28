import { Players } from "@rbxts/services";
import { MainUIController } from "client/ui/MainUIController";
import { FormatCash } from "shared/NumberFormat";

// Renders the local player's Money attribute into a TextLabel named "MoneyText"
// sitting under MoneyParent inside MainUI. The attribute is set by the server
// (PlayerDataService) and auto-replicates to this client.

const ATTRIBUTE = "Money";
const LABEL_NAME = "MoneyText";

function findLabel(): TextLabel | undefined {
	const moneyParent = MainUIController.getMoneyParent();
	if (!moneyParent) return undefined;
	const found = moneyParent.FindFirstChild(LABEL_NAME, true);
	return found?.IsA("TextLabel") ? found : undefined;
}

export function init(): void {
	const player = Players.LocalPlayer;

	const refresh = () => {
		const label = findLabel();
		if (!label) return;
		const value = (player.GetAttribute(ATTRIBUTE) as number | undefined) ?? 0;
		label.Text = FormatCash(value);
	};

	refresh();
	player.GetAttributeChangedSignal(ATTRIBUTE).Connect(refresh);

	// Label may not exist yet on first frame — re-render on new descendants
	const gui = player.WaitForChild("PlayerGui") as PlayerGui;
	gui.DescendantAdded.Connect((desc) => {
		if (desc.Name === LABEL_NAME && desc.IsA("TextLabel")) refresh();
	});
}
