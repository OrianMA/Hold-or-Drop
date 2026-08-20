import { CollectionService, ReplicatedStorage } from "@rbxts/services";
import { Room } from "server/rooms/Room";
import { PlayerProgressionService } from "server/services/PlayerProgressionService";
import { RocketLauncher, ROCKET_MODEL, NITRO_PART } from "server/modules/RocketLauncher";
import { MEGA_ROCKET_SCALE, MEGA_ROCKET_TAG, hasMegaRocket } from "shared/MegaRocketConfig";

// Picks the right rocket for the room's occupant and instantiates it on the pad.
//
// The rockets are authored in ReplicatedStorage/RocketModels as RocketLvl1..RocketLvlN.
// The chosen level tracks the player's Rebirths count: rebirth N → RocketLvlN, clamped
// to [1, N_rockets] (rebirth 0 falls back to Lvl1 since there is no Lvl0, and a rebirth
// count above the number of rockets gets the highest one). The clone is renamed to the
// stable ROCKET_MODEL name so RocketLauncher (§6.17) drives it regardless of its level.

const ROCKET_MODELS_FOLDER = "RocketModels";
const ROCKET_PREFIX = "RocketLvl";

// rebirth count → 1-based rocket level, clamped to the number of authored rockets.
function rocketLevelFor(rebirths: number, count: number): number {
	return math.clamp(rebirths, 1, count);
}

// Remove the room's current rocket and drop the launcher caches that referenced it
// (rooms are reused across occupants, so the cached body parts would otherwise dangle).
function removeRocket(room: Room): void {
	const existing = room.movableModel.FindFirstChild(ROCKET_MODEL);
	if (existing) existing.Destroy();
	RocketLauncher.clearRocketCache(room);
}

export const RocketPlacer = {
	// (Re)place the room's rocket to match its current occupant's rebirth level.
	// Removes any rocket already on the pad and clears the launcher's stale caches
	// (rooms are reused across occupants), then clones, anchors and pivots the new one.
	place(room: Room): void {
		const spawnPoint = room.rocketSpawnPoint;
		if (!spawnPoint) return; // Room already warned about the missing marker

		const player = room.getOccupant();
		if (!player) return;

		const folder = ReplicatedStorage.FindFirstChild(ROCKET_MODELS_FOLDER);
		if (!folder) {
			warn(`RocketPlacer: ReplicatedStorage/${ROCKET_MODELS_FOLDER} not found`);
			return;
		}

		const count = folder.GetChildren().size();
		if (count === 0) {
			warn(`RocketPlacer: ${ROCKET_MODELS_FOLDER} is empty`);
			return;
		}

		const level = rocketLevelFor(PlayerProgressionService.getRebirths(player), count);
		const template = folder.FindFirstChild(`${ROCKET_PREFIX}${level}`);
		if (!template || !template.IsA("Model")) {
			warn(`RocketPlacer: ${ROCKET_PREFIX}${level} missing or not a Model`);
			return;
		}

		// Clear the old rocket + the launcher caches that referenced it before swapping.
		removeRocket(room);

		const rocket = template.Clone();
		rocket.Name = ROCKET_MODEL;
		// Prepare the rocket for its at-rest state on the pad:
		//  - anchor every body part (some templates ship with unanchored parts that would
		//    otherwise fall; this is also the state the launcher expects — it unanchors on
		//    explode and re-anchors on reset),
		//  - turn the engine emitters OFF (templates author them inconsistently; the
		//    launcher lights them on launch and extinguishes them on every ending).
		for (const d of rocket.GetDescendants()) {
			if (d.IsA("BasePart")) {
				d.Anchored = true;
			} else if (
				(d.IsA("Fire") || d.IsA("ParticleEmitter") || d.IsA("Smoke")) &&
				d.FindFirstAncestor(NITRO_PART) !== undefined
			) {
				d.Enabled = false;
			}
		}
		rocket.Parent = room.movableModel;

		// Mega Rocket (§6.24) : le joueur a une Mega Rocket en attente → la fusée posée
		// est légèrement plus grande et porte le tag qui déclenche l'arc-en-ciel côté
		// client (MegaRocketVisuals). ScaleTo agit autour du pivot, donc avant le
		// recalage sur RocketSpawnPoint juste en dessous.
		//
		// ScaleTo prend une échelle ABSOLUE, pas un facteur : les templates ne sont pas
		// tous authored à 1 (RocketLvl2 est à 1.5), donc un ScaleTo(1.15) sec RÉTRÉCIT
		// ceux-là au lieu de les grossir. On multiplie l'échelle courante.
		if (hasMegaRocket(player)) {
			rocket.ScaleTo(rocket.GetScale() * MEGA_ROCKET_SCALE);
			CollectionService.AddTag(rocket, MEGA_ROCKET_TAG);
		}

		// Move the rocket's pivot exactly onto RocketSpawnPoint's position (orientation
		// kept as authored). RocketSpawnPoint is the authoritative placement marker — if a
		// template's pivot isn't at its base, part of the rocket may sit below the floor;
		// that's an authoring detail to fix on the template, not something to compensate
		// for here.
		const pivot = rocket.GetPivot();
		rocket.PivotTo(pivot.add(spawnPoint.Position.sub(pivot.Position)));
	},

	// Remove the room's rocket — called when the room becomes empty so an unoccupied
	// room shows no rocket on its pad.
	clear(room: Room): void {
		removeRocket(room);
	},
};
