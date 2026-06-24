// Single source of truth for the per-room slot colours. Both the neon pipes
// (NeonPipeColors) and the room spotlights (RoomSpotlights) read from here, so a
// retune stays in one place and the spotlight colour always matches the neon one.

// Slot has no player — grey. Shared "off" baseline for pipes and spotlights.
export const EMPTY_COLOR = Color3.fromRGB(120, 120, 120);

// Room/folder name (P1..P5) → slot colour. Add/rename entries to match PlayerZones.
export const ROOM_COLORS = new Map<string, Color3>([
	["P1", Color3.fromRGB(0, 255, 242)], // blue
	["P2", Color3.fromRGB(255, 15, 15)], // red
	["P3", Color3.fromRGB(255, 250, 0)], // yellow
	["P4", Color3.fromRGB(15, 255, 56)], // green
	["P5", Color3.fromRGB(181, 23, 255)], // purple
]);

// Colour for a slot, falling back to grey for an unknown name.
export function roomColor(roomName: string): Color3 {
	return ROOM_COLORS.get(roomName) ?? EMPTY_COLOR;
}
