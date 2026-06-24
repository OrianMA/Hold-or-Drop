import { Workspace } from "@rbxts/services";
import { EMPTY_COLOR, roomColor } from "server/modules/RoomColors";

// Drives the per-room spotlight (Workspace/PlayerZones/P{n}/SpotLight) from room
// occupancy, mirroring NeonPipeColors: the lamp lights up in the slot colour while
// the room is owned and turns OFF when empty — same on/off feel as the neon pipes.
//
// Each SpotLight model has one Neon `LightSource` part (the glowing lens) holding a
// single `SurfaceLight` (the projected cone). We tint the lens + light together and
// toggle the SurfaceLight; the metal/plastic housing parts are left untouched.
//
// Driven by RoomService: setOccupied(room.name) on assign, setEmpty(room.name) on
// release. init() turns every lamp off — the empty / server-start baseline.

const PLAYER_ZONES = "PlayerZones";
const SPOTLIGHT = "SpotLight";
const LIGHT_SOURCE = "LightSource";

interface Lamp {
	lens: BasePart; // Neon part that glows the slot colour
	light: SurfaceLight; // projected cone, disabled while the lamp is off
}

// Resolve + cache each room's lamp once — the instance set never changes at runtime.
// Cached `undefined` means "looked up, not found" so we warn only once per slot.
const lampByRoom = new Map<string, Lamp | undefined>();

function resolveLamp(roomName: string): Lamp | undefined {
	if (lampByRoom.has(roomName)) return lampByRoom.get(roomName);

	const model = Workspace.FindFirstChild(PLAYER_ZONES)?.FindFirstChild(roomName)?.FindFirstChild(SPOTLIGHT);
	const lens = model?.FindFirstChild(LIGHT_SOURCE);
	const light = lens?.FindFirstChildWhichIsA("SurfaceLight");

	let lamp: Lamp | undefined;
	if (lens && lens.IsA("BasePart") && light) {
		lamp = { lens, light };
	} else {
		warn(`RoomSpotlights: ${roomName} missing SpotLight/${LIGHT_SOURCE}/SurfaceLight`);
	}
	lampByRoom.set(roomName, lamp);
	return lamp;
}

function setLamp(roomName: string, color: Color3, on: boolean): void {
	const lamp = resolveLamp(roomName);
	if (!lamp) return;
	lamp.lens.Color = color;
	lamp.light.Color = color;
	lamp.light.Enabled = on;
}

export const RoomSpotlights = {
	// Turn every lamp off — call once before any room is assigned.
	init(): void {
		const zones = Workspace.FindFirstChild(PLAYER_ZONES);
		if (!zones) {
			warn(`RoomSpotlights: Workspace/${PLAYER_ZONES} not found`);
			return;
		}
		for (const zone of zones.GetChildren()) {
			if (zone.FindFirstChild(SPOTLIGHT)) setLamp(zone.Name, EMPTY_COLOR, false);
		}
	},

	// Player took the slot — light the lamp in the slot colour.
	setOccupied(roomName: string): void {
		setLamp(roomName, roomColor(roomName), true);
	},

	// Slot freed — lamp off (grey lens, no projected light).
	setEmpty(roomName: string): void {
		setLamp(roomName, EMPTY_COLOR, false);
	},
};
