-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local rebirthCost = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").rebirthCost
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
-- Drives the persistent HUD progression bar (InGameUI/HUD/BottomList/ProgressionBar).
-- It shows the same thing as the Rebirth menu bar (RebirthMenuController): progress
-- toward the next rebirth, Money / rebirthCost(Rebirths). The difference is purely
-- visual — here the fill and the number count up smoothly when the player earns
-- money, instead of snapping.
--
-- A single NumberValue proxy is tweened toward the live Money value (same pattern as
-- MoneyDisplay). On every Changed step we mirror the proxy into both the fill width
-- (X-scale = money/cost) and the "money / cost" label, so the two stay perfectly in
-- sync through the tween. Mid-flight earnings cancel and restart from the current
-- visual value. A rebirth (cost jumps, money resets) snaps instead of tweening.
local player = Players.LocalPlayer
-- Quad-Out count-up — matches the punchy feel of the money HUD.
local TWEEN_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function getMoney()
	local _condition = (player:GetAttribute("Money"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function getRebirths()
	local _condition = (player:GetAttribute("Rebirths"))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function init()
	local progressionBar = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI"):WaitForChild("HUD"):WaitForChild("BottomList"):WaitForChild("ProgressionBar")
	local fill = progressionBar:WaitForChild("CurrentProgressionFrame")
	local moneyNeededText = progressionBar:WaitForChild("BackgroundFrame"):WaitForChild("MoneyNeededText")
	-- The cost only changes on rebirth; cached so the per-step render stays cheap.
	local cost = rebirthCost(getRebirths())
	local displayValue = 0
	local initialized = false
	local activeTween
	local proxy = Instance.new("NumberValue")
	local function render(value)
		local progress = math.clamp(value / cost, 0, 1)
		fill.Size = UDim2.new(progress, 0, 1, 0)
		moneyNeededText.Text = `{FormatNumber(math.floor(value))} / {FormatNumber(cost)}`
	end
	proxy.Changed:Connect(function(v)
		displayValue = v
		render(v)
	end)
	-- Cancel any in-flight tween and head from where we *visually* are toward the
	-- target. Snaps when already there.
	local function tweenTo(target)
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
				proxy.Value = target
			end
		end)
		tween:Play()
	end
	local function onMoneyChanged()
		local money = getMoney()
		-- First update on join: snap so the bar doesn't sweep up from 0 on every load.
		if not initialized then
			initialized = true
			proxy.Value = money
			displayValue = money
			render(money)
			return nil
		end
		tweenTo(money)
	end
	-- On rebirth the cost jumps and money resets — snap to the new state rather than
	-- animating a confusing backwards sweep.
	local function onRebirthChanged()
		if activeTween ~= nil then
			activeTween:Cancel()
			activeTween = nil
		end
		cost = rebirthCost(getRebirths())
		local money = getMoney()
		proxy.Value = money
		displayValue = money
		render(money)
	end
	player:GetAttributeChangedSignal("Money"):Connect(onMoneyChanged)
	player:GetAttributeChangedSignal("Rebirths"):Connect(onRebirthChanged)
	onMoneyChanged()
end
return {
	init = init,
}
