import { Players, Workspace } from "@rbxts/services";
import { WorldTargetId } from "shared/tutorial/TutorialTypes";
import { TutorialUI } from "./TutorialUI";

// Résout une cible de step en instance concrète.
//   "gui"   → chemin slash-séparé sous InGameUI, ex "ButtonMenu/StartButton"
//   "world" → une part du monde. StreamingEnabled est ACTIF : la découverte passe par
//             WaitForChild plutôt qu'un FindFirstChild one-shot (voir RoomPromptController).

const PLAYER_ZONES = "PlayerZones";
const BUTTON_MODEL = "ButtonModel";
const BUTTON_PART = "ButtonPart";
const SHOP = "Shop";
const SHOP_PROMPT_PART = "ProximityPromptPart";
const ASSIGNED_ROOM_ATTR = "AssignedRoom";

export const TutorialTargets = {
	resolveGui(path: string): GuiObject | undefined {
		const root = TutorialUI.getInGameUI();
		if (!root) return undefined;

		let node: Instance | undefined = root;
		for (const part of path.split("/")) {
			node = node?.FindFirstChild(part);
			if (!node) return undefined;
		}
		return node.IsA("GuiObject") ? node : undefined;
	},

	// Peut yielder (WaitForChild) — appeler depuis un task.spawn.
	resolveWorld(id: WorldTargetId): BasePart | undefined {
		if (id === "Shop") {
			const shop = Workspace.WaitForChild(SHOP, 10);
			const part = shop?.WaitForChild(SHOP_PROMPT_PART, 10);
			return part?.IsA("BasePart") ? part : undefined;
		}

		// RoomButton — le bouton de la room ASSIGNÉE au joueur local.
		const roomName = (Players.LocalPlayer.GetAttribute(ASSIGNED_ROOM_ATTR) as string | undefined) ?? "";
		if (roomName === "") return undefined;

		const zones = Workspace.WaitForChild(PLAYER_ZONES, 10);
		const room = zones?.WaitForChild(roomName, 10);
		const model = room?.WaitForChild(BUTTON_MODEL, 10);
		const part = model?.WaitForChild(BUTTON_PART, 10);
		return part?.IsA("BasePart") ? part : undefined;
	},
};
