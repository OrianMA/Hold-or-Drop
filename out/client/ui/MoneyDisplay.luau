-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local InGameUIController = TS.import(script, script.Parent, "InGameUIController").InGameUIController
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
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
-- Son 2D joué à chaque dépôt d'argent dans le HUD (cf. addVisual). Template
-- préchargé en SoundService pour éviter un fetch CDN au premier gain.
local moneyGainTemplate = (function()
	local sound = Instance.new("Sound")
	sound.Name = "MoneyGainTemplate"
	sound.SoundId = AudioConfig.sfx.moneyGain.id
	sound.Volume = AudioConfig.sfx.moneyGain.volume
	sound.Parent = SoundService
	return sound
end)()
local function playMoneyGain()
	local sound = moneyGainTemplate:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
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
local function findLabel()
	local moneyParent = InGameUIController:getMoneyParent()
	if not moneyParent then
		return nil
	end
	local found = moneyParent:FindFirstChild(LABEL_NAME, true)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	return if _result then found else nil
end
local function render(value)
	local label = findLabel()
	if label then
		label.Text = FormatCash(math.floor(value))
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
	addVisual = function(self, amount)
		if amount > 0 then
			playMoneyGain()
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
