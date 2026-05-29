-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- Updates the GainText + CostText labels on every ButtonModel under
-- Workspace/Buttons based on:
--   • the model's BaseCash / Cost / DataName attributes (set by designers)
--   • the local player's Unlocked_<DataName> attribute (replicated by the
--     server's PlayerDataService)
--
-- GainText  → always `FormatCash(BaseCash)`.
-- CostText  → "POSSESSED" when unlocked, else "{cost} money".
--
-- Listens for new buttons being parented (StreamingEnabled / late init) and
-- for the player's unlock attributes changing (purchase happens on the server,
-- auto-replicates here).
local UI_PART_NAME = "UiPart"
local GAIN_LABEL = "GainText"
local COST_LABEL = "CostText"
local UNLOCK_PREFIX = "Unlocked_"
local function findLabel(uiPart, name)
	local found = uiPart:FindFirstChild(name, true)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	return if _result then found else nil
end
local function isUnlocked(dataName)
	return (Players.LocalPlayer:GetAttribute(`{UNLOCK_PREFIX}{dataName}`)) == true
end
local function updateButton(model)
	if not model:IsA("Model") then
		return nil
	end
	local uiPart = model:FindFirstChild(UI_PART_NAME)
	if not uiPart then
		return nil
	end
	local _condition = (model:GetAttribute("BaseCash"))
	if _condition == nil then
		_condition = 0
	end
	local baseCash = _condition
	local _condition_1 = (model:GetAttribute("Cost"))
	if _condition_1 == nil then
		_condition_1 = 0
	end
	local cost = _condition_1
	local _condition_2 = (model:GetAttribute("DataName"))
	if _condition_2 == nil then
		_condition_2 = model.Name
	end
	local dataName = _condition_2
	local gainLabel = findLabel(uiPart, GAIN_LABEL)
	if gainLabel then
		gainLabel.Text = FormatCash(baseCash)
	end
	local costLabel = findLabel(uiPart, COST_LABEL)
	if costLabel then
		-- Free buttons are owned by default — show POSSESSED regardless of unlock state.
		local owned = cost <= 0 or isUnlocked(dataName)
		costLabel.Text = if owned then "POSSESSED" else `{FormatCash(cost)} money`
	end
end
local function refreshAll(buttonsFolder)
	for _, model in buttonsFolder:GetChildren() do
		updateButton(model)
	end
end
local function init()
	local buttonsFolder = Workspace:WaitForChild("Buttons", 10)
	if not buttonsFolder then
		warn("ButtonLabelsController: Workspace/Buttons not found")
		return nil
	end
	-- ── Attach listeners BEFORE the initial pass ─────────────────────────────
	-- The server's PlayerDataService.setupPlayer yields on DataStore:GetAsync
	-- before calling SetAttribute("Unlocked_X", true). If we did the initial
	-- refresh first and *then* attached the listener, a SetAttribute landing
	-- in between would be silently missed (the attribute is set but no signal
	-- fires because nobody was listening yet, and the refresh already ran).
	-- Listener first → refresh second guarantees we never miss a transition.
	-- New buttons (e.g. streamed in or added at runtime)
	buttonsFolder.ChildAdded:Connect(function(model)
		return updateButton(model)
	end)
	-- Unlock state changes — re-render every button whose DataName matches.
	Players.LocalPlayer.AttributeChanged:Connect(function(attrName)
		if string.sub(attrName, 1, #UNLOCK_PREFIX) ~= UNLOCK_PREFIX then
			return nil
		end
		local dataName = string.sub(attrName, #UNLOCK_PREFIX + 1)
		for _, model in buttonsFolder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local _condition = (model:GetAttribute("DataName"))
			if _condition == nil then
				_condition = model.Name
			end
			local modelDataName = _condition
			if modelDataName == dataName then
				updateButton(model)
			end
		end
	end)
	-- Initial pass — picks up any unlocks already replicated by the time we
	-- get here (the common case when the player rejoins with saved unlocks).
	refreshAll(buttonsFolder)
	-- Belt-and-braces refresh after a short delay in case DataStore was slow
	-- and the unlock attributes arrive *after* both the initial pass and the
	-- listener attachment (which would catch them anyway, but this covers any
	-- edge case where the AttributeChanged signal is missed for an unknown
	-- reason — e.g. the listener seeing the first batch as a single fire).
	task.delay(2, function()
		return refreshAll(buttonsFolder)
	end)
end
return {
	init = init,
}
