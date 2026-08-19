// ── Audio registry ──────────────────────────────────────────────────────────────
// Single source of truth for every sound asset in the game: music and SFX.
// Shared so the client (music + client SFX) and the server (3D explosion SFX)
// reference the same IDs/volumes. The playback logic stays where it lives —
// only the asset definitions are centralised here.

export const AudioConfig = {
	// Background music — a playlist played in a loop. Add tracks to `playlist`;
	// MusicController advances through them and loops back to the start.
	bgm: {
		playlist: ["rbxassetid://93145377732572"],
		volume: 0.3,
	},
	// High-altitude ascent track — crossfades in once the rocket climbs past the
	// altitude threshold (HIGH_ALTITUDE_MUSIC_THRESHOLD in RocketLaunchBehavior),
	// then crossfades back out to the base BGM when the run ends. Loops meanwhile.
	highAltitude: {
		id: "rbxassetid://104868013423076",
		volume: 0.3,
	},
	// Sound effects — still played from their existing call sites; only the
	// asset IDs/volumes are centralised here.
	sfx: {
		explosion: { id: "rbxassetid://139771888058836", volume: 0.8 }, // server, 3D
		rocketLaunch: { id: "rbxassetid://136678911797673", volume: 0.5 }, // server, 3D, en boucle — moteur de la fusée pendant l'ascension (RocketLauncher)
		buttonExplode: { id: "rbxassetid://133384716023284", volume: 1 }, // client
		buttonUpgrade: { id: "rbxassetid://90808623060870", volume: 0.5 }, // client, 3D — son électrique à l'arrivée du pulse néon au bouton (NeonPipePulse)
		moneyGain: { id: "rbxassetid://120891770644830", volume: 0.6 }, // client, 2D — joué à chaque dépôt d'argent dans le HUD (MoneyDisplay.addVisual)
		uiClick: { id: "rbxassetid://72264591133889", volume: 0.5 }, // client, 2D — clic sur n'importe quel bouton de l'UI (UiClickSound)
		perfectClaim: { id: "rbxassetid://3406813517", volume: 0.8 }, // client, 2D — flashs "PERFECT CLAIM" (rouge) et "CRITICAL CLAIM" (doré) (ClaimFlashText)
		information: { id: "rbxassetid://130467592920597", volume: 0.5 }, // client, 2D — apparition d'un bandeau InformationText (Common/Rare/Epic)
		informationLegendary: { id: "rbxassetid://137502807803779", volume: 0.6 }, // client, 2D — apparition d'un bandeau InformationText Legendary
	},
} as const;
