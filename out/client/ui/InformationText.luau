-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Generic "flash text in the HUD" controller.
-- Animates InGameUI/InformationTextCanvasGroup with the same timings as the old
-- ButtonFinishGame/FinishTextCanvasGroup (which it replaces). The contained
-- TextLabel's Text and TextColor3 are overwritten on each show() call.
--
--   InformationText.show("Finish");                           // white, default
--   InformationText.show("Not enough money", new Color3(1, 0, 0));  // red
--
-- Calling show() while a previous flash is mid-animation cancels it cleanly
-- and restarts from full transparency so the new message isn't lost.
local FADE_IN_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DEFAULT_HOLD = 0.2
local DEFAULT_COLOR = Color3.new(1, 1, 1)
local CANVAS_NAME = "InformationTextCanvasGroup"
local LABEL_NAME = "InformationText"
local cachedCanvas
local activeTweens = {}
local activeDelayToken = 0
local function findCanvas()
	if cachedCanvas and cachedCanvas.Parent ~= nil then
		return cachedCanvas
	end
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end
	for _, desc in gui:GetDescendants() do
		if desc.Name == CANVAS_NAME and desc:IsA("CanvasGroup") then
			cachedCanvas = desc
			return desc
		end
	end
	return nil
end
-- Specifically named TextLabel ("InformationText") — recursive search covers
-- the canonical InformationTextCanvasGroup → FrameParent → InformationText
-- path as well as any future re-layout.
local function findLabel(canvas)
	local found = canvas:FindFirstChild(LABEL_NAME, true)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	return if _result then found else nil
end
local function cancelActive()
	for _, t in activeTweens do
		t:Cancel()
	end
	activeTweens = {}
	activeDelayToken += 1
end
local InformationText = {
	FADE_IN_TIME = FADE_IN_TI.Time,
	HOLD_TIME = DEFAULT_HOLD,
	FADE_OUT_TIME = FADE_OUT_TI.Time,
	hide = function(self)
		local canvas = findCanvas()
		if not canvas then
			return nil
		end
		cancelActive()
		canvas.GroupTransparency = 1
	end,
	show = function(self, text, color, holdSeconds)
		local canvas = findCanvas()
		if not canvas then
			warn(`InformationText: {CANVAS_NAME} not found under PlayerGui`)
			return nil
		end
		local label = findLabel(canvas)
		if label then
			label.Text = text
			label.TextColor3 = color or DEFAULT_COLOR
		end
		cancelActive()
		local myToken = activeDelayToken
		canvas.GroupTransparency = 1
		canvas.Visible = true
		local fadeIn = TweenService:Create(canvas, FADE_IN_TI, {
			GroupTransparency = 0,
		})
		table.insert(activeTweens, fadeIn)
		fadeIn:Play()
		local _condition = holdSeconds
		if _condition == nil then
			_condition = DEFAULT_HOLD
		end
		local hold = _condition
		task.delay(FADE_IN_TI.Time + hold, function()
			-- A newer show() invalidated this fade-out — bail.
			if myToken ~= activeDelayToken then
				return nil
			end
			local fadeOut = TweenService:Create(canvas, FADE_OUT_TI, {
				GroupTransparency = 1,
			})
			table.insert(activeTweens, fadeOut)
			fadeOut:Play()
		end)
	end,
}
local function init()
	Events.InformationTextEvent.OnClientEvent:Connect(function(text, color, holdSeconds)
		InformationText:show(text, color, holdSeconds)
	end)
end
return {
	init = init,
	InformationText = InformationText,
}
