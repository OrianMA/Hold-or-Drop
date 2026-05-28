-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local MainUIController = TS.import(script, script.Parent, "MainUIController").MainUIController
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- Renders the local player's Money attribute into a TextLabel named "MoneyText"
-- sitting under MoneyParent inside MainUI. The attribute is set by the server
-- (PlayerDataService) and auto-replicates to this client.
--
-- Updates animate via a NumberValue proxy tweened with TweenService — the
-- label text is re-formatted on every Changed step, so the player sees the
-- number visibly ticking up from the previous balance to the new one. This
-- pattern is robust to mid-flight interruption (e.g. earning more money while
-- the previous tween is still running): we cancel, restart from the current
-- visual value, and head toward the new target.
local ATTRIBUTE = "Money"
local LABEL_NAME = "MoneyText"
-- Duration of the "count-up" animation. Quad-Out feels punchier than Linear —
-- fast start, decelerating finish, matching how popular idle games render
-- reward deltas.
local TWEEN_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function findLabel()
	local moneyParent = MainUIController:getMoneyParent()
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
local function init()
	local player = Players.LocalPlayer
	-- Persistent proxy + the value we last rendered. We tween the proxy and
	-- mirror its value into the label on every Changed step.
	local proxy = Instance.new("NumberValue")
	local displayValue = 0
	local initialized = false
	local activeTween
	local proxyConn
	proxy.Changed:Connect(function(v)
		displayValue = v
		local label = findLabel()
		if label then
			label.Text = FormatCash(math.floor(v))
		end
	end)
	local refresh = function()
		local _condition = (player:GetAttribute(ATTRIBUTE))
		if _condition == nil then
			_condition = 0
		end
		local target = _condition
		-- First update on join (or first time the label appears): snap, no tween,
		-- so the HUD doesn't count up from 0 every time the player loads in.
		if not initialized then
			initialized = true
			proxy.Value = target
			displayValue = target
			local label = findLabel()
			if label then
				label.Text = FormatCash(target)
			end
			return nil
		end
		-- Already at target → nothing to animate. Still cancel any in-flight
		-- tween so it doesn't overshoot the (now stale) previous target.
		if math.floor(displayValue) == target then
			if activeTween ~= nil then
				activeTween:Cancel()
				activeTween = nil
			end
			proxy.Value = target
			return nil
		end
		-- Cancel any in-flight tween and restart from where we *visually* are,
		-- not where the previous tween was supposed to land. Without this, a
		-- quick succession of credits would jump-cut to the latest target.
		if activeTween ~= nil then
			activeTween:Cancel()
			activeTween = nil
		end
		if proxyConn ~= nil then
			proxyConn:Disconnect()
			proxyConn = nil
		end
		proxy.Value = displayValue
		activeTween = TweenService:Create(proxy, TWEEN_INFO, {
			Value = target,
		})
		local tween = activeTween
		-- On completion, snap to the exact target — float interpolation can
		-- leave a 1-unit gap that would render as e.g. "$1999" instead of "$2K".
		local completedConn
		completedConn = tween.Completed:Connect(function()
			completedConn:Disconnect()
			if activeTween == tween then
				activeTween = nil
				proxy.Value = target
				local label = findLabel()
				if label then
					label.Text = FormatCash(target)
				end
			end
		end)
		tween:Play()
	end
	refresh()
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(refresh)
	-- Label may not exist yet on first frame — re-render on new descendants
	local gui = player:WaitForChild("PlayerGui")
	gui.DescendantAdded:Connect(function(desc)
		if desc.Name == LABEL_NAME and desc:IsA("TextLabel") then
			-- Label just appeared — render current value snapped (no tween),
			-- otherwise it would animate from 0 to current on first display.
			desc.Text = FormatCash(math.floor(displayValue))
		end
	end)
end
return {
	init = init,
}
