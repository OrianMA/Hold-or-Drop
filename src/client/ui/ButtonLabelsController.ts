import { Players, Workspace } from "@rbxts/services";
import { FormatCash } from "shared/NumberFormat";

// Updates the GainText + CostText labels on every ButtonModel under
// Workspace/Buttons based on:
//   • the model's BaseCash / Cost / DataName attributes (set by designers)
//   • the local player's Unlocked_<DataName> attribute (replicated by the
//     server's PlayerDataService)
//
// GainText  → always `FormatCash(BaseCash)`.
// CostText  → "POSSESSED" when unlocked, else "{cost} money".
//
// Listens for new buttons being parented (StreamingEnabled / late init) and
// for the player's unlock attributes changing (purchase happens on the server,
// auto-replicates here).

const UI_PART_NAME = "UiPart";
const GAIN_LABEL = "GainText";
const COST_LABEL = "CostText";
const UNLOCK_PREFIX = "Unlocked_";

function findLabel(uiPart: Instance, name: string): TextLabel | undefined {
	const found = uiPart.FindFirstChild(name, true);
	return found?.IsA("TextLabel") ? found : undefined;
}

function isUnlocked(dataName: string): boolean {
	return (Players.LocalPlayer.GetAttribute(`${UNLOCK_PREFIX}${dataName}`) as boolean | undefined) === true;
}

function updateButton(model: Instance): void {
	if (!model.IsA("Model")) return;
	const uiPart = model.FindFirstChild(UI_PART_NAME);
	if (!uiPart) return;

	const baseCash = (model.GetAttribute("BaseCash") as number | undefined) ?? 0;
	const cost = (model.GetAttribute("Cost") as number | undefined) ?? 0;
	const dataName = (model.GetAttribute("DataName") as string | undefined) ?? model.Name;

	const gainLabel = findLabel(uiPart, GAIN_LABEL);
	if (gainLabel) gainLabel.Text = FormatCash(baseCash);

	const costLabel = findLabel(uiPart, COST_LABEL);
	if (costLabel) {
		// Free buttons are owned by default — show POSSESSED regardless of unlock state.
		const owned = cost <= 0 || isUnlocked(dataName);
		costLabel.Text = owned ? "POSSESSED" : `${FormatCash(cost)} money`;
	}
}

function refreshAll(buttonsFolder: Instance): void {
	for (const model of buttonsFolder.GetChildren()) updateButton(model);
}

export function init(): void {
	const buttonsFolder = Workspace.WaitForChild("Buttons", 10);
	if (!buttonsFolder) {
		warn("ButtonLabelsController: Workspace/Buttons not found");
		return;
	}

	// ── Attach listeners BEFORE the initial pass ─────────────────────────────
	// The server's PlayerDataService.setupPlayer yields on DataStore:GetAsync
	// before calling SetAttribute("Unlocked_X", true). If we did the initial
	// refresh first and *then* attached the listener, a SetAttribute landing
	// in between would be silently missed (the attribute is set but no signal
	// fires because nobody was listening yet, and the refresh already ran).
	// Listener first → refresh second guarantees we never miss a transition.

	// New buttons (e.g. streamed in or added at runtime)
	buttonsFolder.ChildAdded.Connect((model) => updateButton(model));

	// Unlock state changes — re-render every button whose DataName matches.
	Players.LocalPlayer.AttributeChanged.Connect((attrName) => {
		if (string.sub(attrName, 1, UNLOCK_PREFIX.size()) !== UNLOCK_PREFIX) return;
		const dataName = string.sub(attrName, UNLOCK_PREFIX.size() + 1);
		for (const model of buttonsFolder.GetChildren()) {
			if (!model.IsA("Model")) continue;
			const modelDataName = (model.GetAttribute("DataName") as string | undefined) ?? model.Name;
			if (modelDataName === dataName) updateButton(model);
		}
	});

	// Initial pass — picks up any unlocks already replicated by the time we
	// get here (the common case when the player rejoins with saved unlocks).
	refreshAll(buttonsFolder);

	// Belt-and-braces refresh after a short delay in case DataStore was slow
	// and the unlock attributes arrive *after* both the initial pass and the
	// listener attachment (which would catch them anyway, but this covers any
	// edge case where the AttributeChanged signal is missed for an unknown
	// reason — e.g. the listener seeing the first batch as a single fire).
	task.delay(2, () => refreshAll(buttonsFolder));
}
