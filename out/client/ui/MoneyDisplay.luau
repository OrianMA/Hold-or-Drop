-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
local playCashSound = TS.import(script, script.Parent.Parent, "audio", "CashSound").playCashSound
-- Renders the local player's Money attribute into a TextLabel named "MoneyText"
-- sitting under MoneyParent inside the InGameUI HUD. The attribute is set by the server
-- (PlayerDataService) and auto-replicates to this client.
--
-- Updates animate via a NumberValue proxy tweened with TweenService — the label
-- text is re-formatted on every Changed step, so the player sees the number
-- visibly ticking from the previous balance to the new one. Robust to mid-flight
-- interruption (e.g. earning more while a tween runs): we cancel, restart from
-- the current visual value, and head toward the new target.
--
-- `addVisual` lets other UI (e.g. the end-game payout animation) drive the HUD
-- up incrementally for cosmetic effect. The Money attribute stays the source of
-- truth — when the server credit lands, refresh() reconciles to the same value
-- with no visible jump.
local ATTRIBUTE = "Money"
local LABEL_NAME = "MoneyText"
-- Son 2D joué à chaque dépôt d'argent dans le HUD (cf. addVisual).
local function playMoneyGain(options)
	playCashSound(options)
end
-- Duration of the "count-up" animation. Quad-Out feels punchier than Linear.
local TWEEN_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Persistent proxy + the value we last rendered. We tween the proxy and mirror
-- its value into the label on every Changed step. `currentTarget` is the value
-- the proxy is currently heading toward (attribute- or addVisual-driven).
local proxy
local displayValue = 0
local currentTarget = 0
local initialized = false
local activeTween
-- Other HUD elements (e.g. the rebirth progression bar) can mirror the *displayed*
-- money so they animate in perfect lockstep with this counter — including the
-- cosmetic count-up driven by `addVisual` during the payout. Each subscriber is
-- called on every render step, and once immediately on subscribe with the current
-- value.
local listeners = {}
local function notify(value)
	for _, fn in listeners do
		fn(value)
	end
end
-- Every "MoneyText" label under the InGameUI shows the balance — the HUD's own
-- (inside HUD/MoneyParent) and the shop-time one (InGameUI/MoneyParent/ListFrame),
-- which is shown while the HUD is hidden during shopping. Update them all.
local function findLabels()
	local _inGameUI = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if _inGameUI ~= nil then
		_inGameUI = _inGameUI:FindFirstChild("InGameUI")
	end
	local inGameUI = _inGameUI
	if not inGameUI then
		return {}
	end
	local labels = {}
	for _, desc in inGameUI:GetDescendants() do
		if desc.Name == LABEL_NAME and desc:IsA("TextLabel") then
			table.insert(labels, desc)
		end
	end
	return labels
end
local function render(value)
	local text = FormatCash(math.floor(value))
	for _, label in findLabels() do
		label.Text = text
	end
end
-- Cancel any in-flight tween and head from where we *visually* are toward
-- `target`. Snaps instead of tweening when we're already there.
local function tweenTo(target)
	currentTarget = target
	if not proxy then
		return nil
	end
	if activeTween ~= nil then
		activeTween:Cancel()
		activeTween = nil
	end
	if math.floor(displayValue) == math.floor(target) then
		proxy.Value = target
		return nil
	end
	proxy.Value = displayValue
	local tween = TweenService:Create(proxy, TWEEN_INFO, {
		Value = target,
	})
	activeTween = tween
	local completed
	completed = tween.Completed:Connect(function()
		completed:Disconnect()
		if activeTween == tween then
			activeTween = nil
			if proxy then
				proxy.Value = target
			end
			render(target)
		end
	end)
	tween:Play()
end
local function refresh()
	local _condition = (Players.LocalPlayer:GetAttribute(ATTRIBUTE))
	if _condition == nil then
		_condition = 0
	end
	local target = _condition
	-- First update on join: snap, no tween, so the HUD doesn't count up from 0
	-- every time the player loads in.
	if not initialized then
		initialized = true
		if proxy then
			proxy.Value = target
		end
		displayValue = target
		currentTarget = target
		render(target)
		return nil
	end
	tweenTo(target)
end
local MoneyDisplay = {
	init = function(self)
		local player = Players.LocalPlayer
		proxy = Instance.new("NumberValue")
		proxy.Changed:Connect(function(v)
			displayValue = v
			render(v)
			notify(v)
		end)
		refresh()
		player:GetAttributeChangedSignal(ATTRIBUTE):Connect(refresh)
		-- Label may not exist yet on first frame — re-render on new descendants.
		local gui = player:WaitForChild("PlayerGui")
		gui.DescendantAdded:Connect(function(desc)
			if desc.Name == LABEL_NAME and desc:IsA("TextLabel") then
				desc.Text = FormatCash(math.floor(displayValue))
			end
		end)
	end,
	addVisual = function(self, amount, sound)
		if amount > 0 then
			playMoneyGain(sound)
		end
		tweenTo(currentTarget + amount)
	end,
	subscribe = function(self, fn)
		local _fn = fn
		table.insert(listeners, _fn)
		fn(displayValue)
	end,
}
return {
	MoneyDisplay = MoneyDisplay,
}
