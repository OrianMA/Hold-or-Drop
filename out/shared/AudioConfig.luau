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
	highAltitude = {
		id = "rbxassetid://104868013423076",
		volume = 0.3,
	},
	sfx = {
		explosion = {
			id = "rbxassetid://139771888058836",
			volume = 0.8,
		},
		rocketLaunch = {
			id = "rbxassetid://136678911797673",
			volume = 0.5,
		},
		buttonExplode = {
			id = "rbxassetid://133384716023284",
			volume = 1,
		},
		buttonUpgrade = {
			id = "rbxassetid://90808623060870",
			volume = 0.5,
		},
		moneyGain = {
			id = "rbxassetid://120891770644830",
			volume = 0.6,
		},
		uiClick = {
			id = "rbxassetid://72264591133889",
			volume = 0.5,
		},
	},
}
return {
	AudioConfig = AudioConfig,
}
