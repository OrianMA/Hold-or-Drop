-- Compiled with roblox-ts v3.0.0
-- ── Audio registry ──────────────────────────────────────────────────────────────
-- Single source of truth for every sound asset in the game: music and SFX.
-- Shared so the client (music + client SFX) and the server (3D explosion SFX)
-- reference the same IDs/volumes. The playback logic stays where it lives —
-- only the asset definitions are centralised here.
local AudioConfig = {
	bgm = {
		playlist = { "rbxassetid://93145377732572" },
		volume = 0.3,
	},
	buttonGame = {
		id = "rbxassetid://103902037806976",
		volume = 0.5,
	},
	sfx = {
		explosion = {
			id = "rbxassetid://139771888058836",
			volume = 0.8,
		},
		buttonExplode = {
			id = "rbxassetid://133384716023284",
			volume = 1,
		},
		parry = {
			id = "rbxassetid://119580857539801",
			volume = 1,
		},
		buttonUpgrade = {
			id = "",
			volume = 0.6,
		},
	},
}
return {
	AudioConfig = AudioConfig,
}
