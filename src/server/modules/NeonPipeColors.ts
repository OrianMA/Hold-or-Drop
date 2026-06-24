import { Workspace } from "@rbxts/services";
import { EMPTY_COLOR, ROOM_COLORS } from "server/modules/RoomColors";

// Colours the Workspace/Environment/NeonPipe/P{n} pipes to match the player
// holding that room slot. The room name (P1..P5) maps 1:1 to a NeonPipe/P{n}
// folder, so the colour is chosen by slot, not by join order.
//
// Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name)
// on release. init() greys every pipe — the empty / server-start baseline.

// Colours are slot-keyed and shared with the room spotlights — see RoomColors.

const ENVIRONMENT = "Environment";
const NEON_PIPE = "NeonPipe";
// Incremented on each successful purchase for a slot; the client (NeonPipePulse)
// watches this attribute to run the travelling-segment animation.
const PULSE_ATTR = "Pulse";

// Walk each P{n} folder once and cache its parts — colour changes are frequent
// (every assign/release) but the part set never changes at runtime.
const partsByRoom = new Map<string, BasePart[]>();

function neonPipeFolder(): Instance | undefined {
	return Workspace.FindFirstChild(ENVIRONMENT)?.FindFirstChild(NEON_PIPE);
}

function resolveParts(roomName: string): BasePart[] {
	const cached = partsByRoom.get(roomName);
	if (cached) return cached;

	const parts: BasePart[] = [];
	const folder = neonPipeFolder()?.FindFirstChild(roomName);
	if (folder) {
		for (const descendant of folder.GetDescendants()) {
			if (descendant.IsA("BasePart")) parts.push(descendant);
		}
	}
	partsByRoom.set(roomName, parts);
	return parts;
}

function paint(roomName: string, color: Color3): void {
	for (const part of resolveParts(roomName)) part.Color = color;
}

export const NeonPipeColors = {
	// Grey every pipe — call once before any room is assigned.
	init(): void {
		const root = neonPipeFolder();
		if (!root) {
			warn(`NeonPipeColors: Workspace/${ENVIRONMENT}/${NEON_PIPE} not found`);
			return;
		}
		for (const folder of root.GetChildren()) paint(folder.Name, EMPTY_COLOR);
	},

	// Player took the slot — light its pipe in the slot colour.
	setOccupied(roomName: string): void {
		paint(roomName, ROOM_COLORS.get(roomName) ?? EMPTY_COLOR);
	},

	// Slot freed — back to grey.
	setEmpty(roomName: string): void {
		paint(roomName, EMPTY_COLOR);
	},

	// Fire a one-shot "purchase" pulse on this slot's pipe. The server only bumps a
	// counter attribute on the NeonPipe/P{n} folder; the actual travelling segment
	// (shop → button) is animated 100% client-side by client/ui/NeonPipePulse — no
	// colour replication, no RemoteEvent.
	pulse(roomName: string): void {
		const folder = neonPipeFolder()?.FindFirstChild(roomName);
		if (!folder) return;
		const current = (folder.GetAttribute(PULSE_ATTR) as number | undefined) ?? 0;
		folder.SetAttribute(PULSE_ATTR, current + 1);
	},
};
