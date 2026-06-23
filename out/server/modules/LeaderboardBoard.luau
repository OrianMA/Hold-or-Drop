-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Cfg = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "LeaderboardConfig")
-- Renders ranked rows into a board's ScrollingFrame. Rows are cloned ONCE from a
-- hidden RowTemplate and reused (text updated in place) so each client's scroll
-- position is preserved across refreshes. CanvasSize is set to the used row count
-- so the scroll stops at the last real entry.
local rowCache = {}
local function buildRows(surface, scroller)
	-- Clear any stale row clones left in the place (earlier session or Edit-time
	-- test) so we never end up with duplicates. The UIListLayout is not a Frame,
	-- and the RowTemplate lives under the SurfaceGui (not here), so both survive.
	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local template = surface:FindFirstChild(Cfg.ROW_TEMPLATE)
	local rows = {}
	if not template then
		return rows
	end
	template.Visible = false
	for i = 1, Cfg.TOP_N do
		local frame = template:Clone()
		frame.Name = `{Cfg.ROW_PREFIX}{i}`
		frame.LayoutOrder = i
		frame.Visible = false
		frame.Parent = scroller
		local _arg0 = {
			frame = frame,
			rank = frame:FindFirstChild(Cfg.ROW_RANK),
			name = frame:FindFirstChild(Cfg.ROW_NAME),
			value = frame:FindFirstChild(Cfg.ROW_VALUE),
		}
		table.insert(rows, _arg0)
	end
	return rows
end
local function getRows(board)
	local surface = board:FindFirstChild(Cfg.BOARD_SURFACE)
	if not surface then
		return nil
	end
	local scroller = surface:FindFirstChild(Cfg.BOARD_ROWS)
	if not scroller then
		return nil
	end
	local rows = rowCache[scroller]
	if not rows then
		rows = buildRows(surface, scroller)
		local _rows = rows
		rowCache[scroller] = _rows
	end
	return rows
end
local function renderBoard(board, entries, format)
	local rows = getRows(board)
	if not rows then
		return nil
	end
	local used = 0
	for i = 0, #rows - 1 do
		local row = rows[i + 1]
		local entry = entries[i + 1]
		if entry then
			row.rank.Text = `{i + 1}`
			row.name.Text = entry.name
			row.value.Text = format(entry.value)
			row.frame.Visible = true
			used += 1
		else
			row.frame.Visible = false
		end
	end
	local scroller = if #rows > 0 then (rows[1].frame.Parent) else nil
	if scroller then
		scroller.CanvasSize = UDim2.new(0, 0, 0, used * Cfg.ROW_HEIGHT)
	end
end
return {
	renderBoard = renderBoard,
}
