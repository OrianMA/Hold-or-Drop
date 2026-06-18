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
	// Music played while the player holds the button. Loops for the whole hold,
	// stops on release or on explosion.
	buttonGame: {
		id: "rbxassetid://103902037806976",
		volume: 0.5,
	},
	// Sound effects — still played from their existing call sites; only the
	// asset IDs/volumes are centralised here.
	sfx: {
		explosion: { id: "rbxassetid://139771888058836", volume: 0.8 }, // server, 3D
		buttonExplode: { id: "rbxassetid://133384716023284", volume: 1 }, // client
		parry: { id: "rbxassetid://119580857539801", volume: 1 }, // client
	},
} as const;
