// Tunables + names for the leaderboards & podium system.
// Single place to retune cadence, sizes, store names, podium animations.
// Imported by both the server logic and (type only) the render modules.

// One ranked row, resolved server-side from an OrderedDataStore entry.
export interface RankedEntry {
	userId: number;
	name: string;
	value: number; // money (cash) or playtime (seconds)
}

// ── Cadence & sizes ──────────────────────────────────────────────────────────
export const REFRESH_INTERVAL = 60; // seconds between full refreshes
export const TOP_N = 50; // entries fetched + stored per leaderboard
export const VISIBLE_ROWS = 15; // rows visible before scrolling (informational)
export const ROW_HEIGHT = 52; // px per row in the ScrollingFrame canvas (50 + 2 padding)
export const WRITE_SPACING = 0.1; // seconds between DataStore writes (smoothing)

// ── OrderedDataStore names (bump suffix to wipe a ranking) ────────────────────
// v2: values are now the monotonic rank encoding (see LeaderboardService), not
// raw cash — a fresh key is required so old raw entries don't mis-sort/mis-decode.
export const MONEY_STORE = "LB_Money_v2";
export const PLAYTIME_STORE = "LB_Playtime_v1";

// ── Studio instance names (under Workspace.Environment.LeaderBoards) ──────────
export const LEADERBOARDS_FOLDER = "LeaderBoards"; // child of Workspace.Environment
export const MONEY_BOARD = "MoneyBoard";
export const PLAYTIME_BOARD = "PlaytimeBoard";
export const PODIUM_FOLDER = "Podium";
export const PODIUM_RIG_PREFIX = "PodiumRig"; // PodiumRig1 (1st) .. PodiumRig3 (3rd)

// SurfaceGui internal structure (built by the Studio build task)
export const BOARD_SURFACE = "Display"; // SurfaceGui
export const BOARD_ROWS = "Rows"; // ScrollingFrame
export const ROW_TEMPLATE = "RowTemplate"; // hidden Frame, sibling of Rows (cloned at runtime)
export const ROW_PREFIX = "Row"; // Row1..RowTOP_N (created at runtime)
export const ROW_RANK = "RankLabel";
export const ROW_NAME = "NameLabel";
export const ROW_VALUE = "ValueLabel";
// (Board header titles are static decoration set once by the Studio build task.)

// ── Podium nameplate + animations ────────────────────────────────────────────
export const PODIUM_NAMEPLATE = "Nameplate"; // BillboardGui built at runtime on each rig's Head
// Standard R15 walk / idle animation assets (swap for custom IDs if desired).
export const WALK_ANIM_ID = "rbxassetid://507777826";
export const IDLE_ANIM_ID = "rbxassetid://507766388";
