-- Compiled with roblox-ts v3.0.0
-- Tunables + names for the leaderboards & podium system.
-- Single place to retune cadence, sizes, store names, podium animations.
-- Imported by both the server logic and (type only) the render modules.
-- One ranked row, resolved server-side from an OrderedDataStore entry.
-- ── Cadence & sizes ──────────────────────────────────────────────────────────
local REFRESH_INTERVAL = 60
local TOP_N = 50
local VISIBLE_ROWS = 15
local ROW_HEIGHT = 52
local WRITE_SPACING = 0.1
-- ── OrderedDataStore names (bump suffix to wipe a ranking) ────────────────────
local MONEY_STORE = "LB_Money_v1"
local PLAYTIME_STORE = "LB_Playtime_v1"
-- ── Studio instance names (under Workspace.Environment.LeaderBoards) ──────────
local LEADERBOARDS_FOLDER = "LeaderBoards"
local MONEY_BOARD = "MoneyBoard"
local PLAYTIME_BOARD = "PlaytimeBoard"
local PODIUM_FOLDER = "Podium"
local PODIUM_RIG_PREFIX = "PodiumRig"
-- SurfaceGui internal structure (built by the Studio build task)
local BOARD_SURFACE = "Display"
local BOARD_ROWS = "Rows"
local ROW_TEMPLATE = "RowTemplate"
local ROW_PREFIX = "Row"
local ROW_RANK = "RankLabel"
local ROW_NAME = "NameLabel"
local ROW_VALUE = "ValueLabel"
-- (Board header titles are static decoration set once by the Studio build task.)
-- ── Podium nameplate + animations ────────────────────────────────────────────
local PODIUM_NAMEPLATE = "Nameplate"
-- Standard R15 walk / idle animation assets (swap for custom IDs if desired).
local WALK_ANIM_ID = "rbxassetid://507777826"
local IDLE_ANIM_ID = "rbxassetid://507766388"
return {
	REFRESH_INTERVAL = REFRESH_INTERVAL,
	TOP_N = TOP_N,
	VISIBLE_ROWS = VISIBLE_ROWS,
	ROW_HEIGHT = ROW_HEIGHT,
	WRITE_SPACING = WRITE_SPACING,
	MONEY_STORE = MONEY_STORE,
	PLAYTIME_STORE = PLAYTIME_STORE,
	LEADERBOARDS_FOLDER = LEADERBOARDS_FOLDER,
	MONEY_BOARD = MONEY_BOARD,
	PLAYTIME_BOARD = PLAYTIME_BOARD,
	PODIUM_FOLDER = PODIUM_FOLDER,
	PODIUM_RIG_PREFIX = PODIUM_RIG_PREFIX,
	BOARD_SURFACE = BOARD_SURFACE,
	BOARD_ROWS = BOARD_ROWS,
	ROW_TEMPLATE = ROW_TEMPLATE,
	ROW_PREFIX = ROW_PREFIX,
	ROW_RANK = ROW_RANK,
	ROW_NAME = ROW_NAME,
	ROW_VALUE = ROW_VALUE,
	PODIUM_NAMEPLATE = PODIUM_NAMEPLATE,
	WALK_ANIM_ID = WALK_ANIM_ID,
	IDLE_ANIM_ID = IDLE_ANIM_ID,
}
