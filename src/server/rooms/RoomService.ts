import { Players, Workspace } from "@rbxts/services";
import { Room } from "./Room";
import { PlayerProgressionService } from "server/services/PlayerProgressionService";
import { NeonPipeColors } from "server/modules/NeonPipeColors";
import { RoomSpotlights } from "server/modules/RoomSpotlights";
import { RocketPlacer } from "server/modules/RocketPlacer";

// Owns the player ↔ room mapping (the "player-only" domain).
//
// At server start it scans Workspace/PlayerZones for P{n} folders (one Button
// model each) and turns each into a Room. Players are assigned the first free
// room in order on join and released on leave. The billboard of an occupied
// room mirrors the occupant's EffectiveBaseCash; empty rooms read "Empty".
//
// The actual button gameplay (ButtonModule) consults getRooms()/owns() — this
// service never touches the hold/risk loop.

const PLAYER_ZONES = "PlayerZones";

const rooms: Room[] = [];
const roomByPlayer = new Map<Player, Room>();
// While a player is assigned, we mirror live BaseCash changes onto their room's
// billboard (covers the DataStore load landing after the initial assign).
const baseCashConns = new Map<Player, RBXScriptConnection>();
// Teleport the occupant onto their room's spawn part on every (re)spawn.
const spawnConns = new Map<Player, RBXScriptConnection>();
// Deferred rocket placement: if progression hasn't loaded when the room is assigned
// (Rebirths attribute still nil), we wait for it once, then place — tracked so it can
// be cleaned up if the player leaves before the load lands.
const rocketConns = new Map<Player, RBXScriptConnection>();

// Place the rocket matching the player's rebirth level. The Rebirths attribute is
// loaded asynchronously by PlayerProgressionService, so it may not be set yet at
// assign time; if so, defer the placement until the attribute first appears.
function placeRocketWhenReady(room: Room, player: Player): void {
	if (player.GetAttribute("Rebirths") !== undefined) {
		RocketPlacer.place(room);
		return;
	}
	const conn = player.GetAttributeChangedSignal("Rebirths").Connect(() => {
		conn.Disconnect();
		rocketConns.delete(player);
		if (room.owns(player)) RocketPlacer.place(room);
	});
	rocketConns.set(player, conn);
}

// "P2" → 2. Numeric-aware so P10 sorts after P9, not after P1.
function roomOrder(name: string): number {
	const [digits] = name.match("%d+");
	return digits !== undefined ? (tonumber(digits) ?? 0) : 0;
}

// Place a character on top of a spawn part.
function teleportToSpawn(character: Model, spawn: BasePart): void {
	const hrp = character.WaitForChild("HumanoidRootPart", 5) as BasePart | undefined;
	if (!hrp) return;
	const playerHeight = character.GetExtentsSize().Y;
	hrp.CFrame = spawn.CFrame.add(new Vector3(0, spawn.Size.Y / 2 + playerHeight / 2, 0));
}

function assign(player: Player): void {
	const room = rooms.find((r) => r.isEmpty());
	if (!room) {
		warn(`RoomService: no free room for ${player.Name} (all ${rooms.size()} rooms occupied)`);
		return;
	}

	room.assign(player);
	roomByPlayer.set(player, room);
	// Tells this player's client which prompt to enable (RoomPromptController).
	player.SetAttribute("AssignedRoom", room.name);
	room.setGainCash(PlayerProgressionService.get(player, "EffectiveBaseCash"));
	// Light this slot's neon pipe + spotlight in the room's colour.
	NeonPipeColors.setOccupied(room.name);
	RoomSpotlights.setOccupied(room.name);

	// Drop the right rocket onto the pad for this player's rebirth level.
	placeRocketWhenReady(room, player);

	// Teleport the player onto their room's spawn part on every (re)spawn, and move
	// an already-spawned character now (service init with players already in-game).
	const spawnPart = room.spawnPart;
	if (spawnPart) {
		const spawnConn = player.CharacterAdded.Connect((character) => teleportToSpawn(character, spawnPart));
		spawnConns.set(player, spawnConn);
		if (player.Character) teleportToSpawn(player.Character, spawnPart);
	}

	const conn = player.GetAttributeChangedSignal("EffectiveBaseCash").Connect(() => {
		room.setGainCash(PlayerProgressionService.get(player, "EffectiveBaseCash"));
	});
	baseCashConns.set(player, conn);
}

function release(player: Player): void {
	const conn = baseCashConns.get(player);
	if (conn) {
		conn.Disconnect();
		baseCashConns.delete(player);
	}

	const spawnConn = spawnConns.get(player);
	if (spawnConn) {
		spawnConn.Disconnect();
		spawnConns.delete(player);
	}

	const rocketConn = rocketConns.get(player);
	if (rocketConn) {
		rocketConn.Disconnect();
		rocketConns.delete(player);
	}

	const room = roomByPlayer.get(player);
	if (!room) return;
	room.release();
	// Empty room → no rocket on the pad.
	RocketPlacer.clear(room);
	roomByPlayer.delete(player);
	player.SetAttribute("AssignedRoom", "");
	// Slot freed — grey its neon pipe + turn the spotlight off.
	NeonPipeColors.setEmpty(room.name);
	RoomSpotlights.setEmpty(room.name);
}

export const RoomService = {
	init(): void {
		// Grey every neon pipe + turn every spotlight off — empty baseline before
		// any assignment below.
		NeonPipeColors.init();
		RoomSpotlights.init();

		const zones = Workspace.WaitForChild(PLAYER_ZONES);

		const children = zones.GetChildren();
		children.sort((a, b) => roomOrder(a.Name) < roomOrder(b.Name));

		for (const child of children) {
			const room = new Room(child);
			if (!room.isValid()) continue;
			room.release(); // clean "Empty" baseline (prompt disabled, billboard reset)
			rooms.push(room);
		}

		// The CommunityJoinPart prompt is now driven entirely client-side: the client
		// opens the native GroupService:PromptJoinAsync card and fires
		// CommunityJoinedEvent on success (wired in BoostService). No server wiring here.

		Players.PlayerAdded.Connect((player) => assign(player));
		for (const player of Players.GetPlayers()) assign(player);

		Players.PlayerRemoving.Connect((player) => release(player));
	},

	getRoom(player: Player): Room | undefined {
		return roomByPlayer.get(player);
	},

	getRooms(): Room[] {
		return rooms;
	},
};
