import { Workspace } from "@rbxts/services";

// Colours the Workspace/Environment/NeonPipe/P{n} pipes to match the player
// holding that room slot. The room name (P1..P5) maps 1:1 to a NeonPipe/P{n}
// folder, so the colour is chosen by slot, not by join order.
//
// Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name)
// on release. init() greys every pipe — the empty / server-start baseline.

// --- Tunable colours (edit here) --------------------------------------------
const EMPTY_COLOR = Color3.fromRGB(120, 120, 120); // grey — slot has no player

// Room/folder name → pipe colour. Add/rename entries to match PlayerZones.
const ROOM_COLORS = new Map<string, Color3>([
	["P1", Color3.fromRGB(0, 255, 242)], // blue
	["P2", Color3.fromRGB(255, 15, 15)], // red
	["P3", Color3.fromRGB(255, 250, 0)], // yellow
	["P4", Color3.fromRGB(15, 255, 56)], // green
	["P5", Color3.fromRGB(181, 23, 255)], // purple
]);
// ----------------------------------------------------------------------------

const ENVIRONMENT = "Environment";
const NEON_PIPE = "NeonPipe";

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
};
