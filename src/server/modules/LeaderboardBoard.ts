import { RankedEntry } from "shared/LeaderboardConfig";
import * as Cfg from "shared/LeaderboardConfig";

// Renders ranked rows into a board's ScrollingFrame. Rows are cloned ONCE from a
// hidden RowTemplate and reused (text updated in place) so each client's scroll
// position is preserved across refreshes. CanvasSize is set to the used row count
// so the scroll stops at the last real entry.

type RowRefs = {
	frame: Frame;
	rank: TextLabel;
	name: TextLabel;
	value: TextLabel;
};

const rowCache = new Map<ScrollingFrame, RowRefs[]>();

function buildRows(surface: SurfaceGui, scroller: ScrollingFrame): RowRefs[] {
	// Clear any stale row clones left in the place (earlier session or Edit-time
	// test) so we never end up with duplicates. The UIListLayout is not a Frame,
	// and the RowTemplate lives under the SurfaceGui (not here), so both survive.
	for (const child of scroller.GetChildren()) {
		if (child.IsA("Frame")) child.Destroy();
	}
	const template = surface.FindFirstChild(Cfg.ROW_TEMPLATE) as Frame | undefined;
	const rows: RowRefs[] = [];
	if (!template) return rows;
	template.Visible = false;
	for (let i = 1; i <= Cfg.TOP_N; i++) {
		const frame = template.Clone();
		frame.Name = `${Cfg.ROW_PREFIX}${i}`;
		frame.LayoutOrder = i;
		frame.Visible = false;
		frame.Parent = scroller;
		rows.push({
			frame,
			rank: frame.FindFirstChild(Cfg.ROW_RANK) as TextLabel,
			name: frame.FindFirstChild(Cfg.ROW_NAME) as TextLabel,
			value: frame.FindFirstChild(Cfg.ROW_VALUE) as TextLabel,
		});
	}
	return rows;
}

function getRows(board: Instance): RowRefs[] | undefined {
	const surface = board.FindFirstChild(Cfg.BOARD_SURFACE) as SurfaceGui | undefined;
	if (!surface) return undefined;
	const scroller = surface.FindFirstChild(Cfg.BOARD_ROWS) as ScrollingFrame | undefined;
	if (!scroller) return undefined;
	let rows = rowCache.get(scroller);
	if (!rows) {
		rows = buildRows(surface, scroller);
		rowCache.set(scroller, rows);
	}
	return rows;
}

export function renderBoard(board: Instance, entries: RankedEntry[], format: (v: number) => string): void {
	const rows = getRows(board);
	if (!rows) return;
	let used = 0;
	for (let i = 0; i < rows.size(); i++) {
		const row = rows[i];
		const entry = entries[i];
		if (entry) {
			row.rank.Text = `${i + 1}`;
			row.name.Text = entry.name;
			row.value.Text = format(entry.value);
			row.frame.Visible = true;
			used += 1;
		} else {
			row.frame.Visible = false;
		}
	}
	const scroller = rows.size() > 0 ? (rows[0].frame.Parent as ScrollingFrame) : undefined;
	if (scroller) scroller.CanvasSize = new UDim2(0, 0, 0, used * Cfg.ROW_HEIGHT);
}
