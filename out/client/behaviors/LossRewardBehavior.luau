-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local MoneyDisplay = TS.import(script, script.Parent.Parent, "ui", "MoneyDisplay").MoneyDisplay
local FloatingCash = TS.import(script, script.Parent.Parent, "ui", "FloatingCash").FloatingCash
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
-- ── Losing-explosion consolation ────────────────────────────────────────────────
--
-- On a losing explosion there is NO ButtonFinishGame popup (see §6.3). Instead the
-- player gets a flat consolation (baseCash / 3, computed server-side) shown as a
-- single "+amount" text that pops up in the middle of the screen, holds, then flies
-- into the money HUD. On arrival it banks the cash (MoneyDisplay.addVisual — count-up
-- + money SFX) and fires EndGameFinishedEvent so the server credits the real Money
-- via the shared pendingEarned path (the HUD reconciles with no jump).
-- Reuse the same floating template the end-game payout sprays (a Frame holding an
-- "Amount" TextLabel), preloaded in ReplicatedStorage.
local FLOATING_TEMPLATE_NAME = "FloatingMultiplierTemplate"
local JUMP_HEIGHT = 90
local JUMP_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local HOLD = 0.7
local FLY_TI = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local cachedTemplate
local function getTemplate()
	if cachedTemplate then
		return cachedTemplate
	end
	local found = ReplicatedStorage:FindFirstChild(FLOATING_TEMPLATE_NAME)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("Frame")
	end
	if _result then
		cachedTemplate = found
	end
	return cachedTemplate
end
local function getScreenGui()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local _found = playerGui
	if _found ~= nil then
		_found = _found:FindFirstChild("InGameUI")
	end
	local found = _found
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("ScreenGui")
	end
	return if _result then found else nil
end
-- Banks the cash and tells the server to credit it (shared with the popup path).
-- Skips banking if a rebirth cancelled this run (gen went stale) so nothing lands
-- after the balance was reset to 0 — the server pending credit is cleared too.
local function bank(amount, gen)
	if not FloatingCash:isStale(gen) then
		MoneyDisplay:addVisual(amount)
		Events.EndGameFinishedEvent:FireServer()
	end
	MusicController.resumeBgm()
end
local function spawnJumpingText(amount)
	local moneyParent = InGameUIController:getMoneyParent()
	local template = getTemplate()
	local screenGui = getScreenGui()
	local runGen = FloatingCash:current()
	-- No target / template / laid-out screen — still bank the cash so the credit lands.
	if not moneyParent or not template or not screenGui or screenGui.AbsoluteSize.X == 0 then
		bank(amount, runGen)
		return nil
	end
	local center = screenGui.AbsoluteSize / 2
	local frame = template:Clone()
	frame.Name = "LossRewardFloatingText"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 30
	frame.Position = UDim2.new(0, center.X, 0, center.Y)
	frame.Visible = true
	frame.Parent = screenGui
	local amountLabel = frame:FindFirstChild("Amount")
	if amountLabel then
		amountLabel.Text = `+{FormatCash(amount)}`
	end
	-- 1. Jump up.
	local jump = TweenService:Create(frame, JUMP_TI, {
		Position = UDim2.new(0, center.X, 0, center.Y - JUMP_HEIGHT),
	})
	jump.Completed:Connect(function()
		-- 2. Brief hold, then fly to the money HUD (target re-read at fly-time).
		task.delay(HOLD, function()
			local _absolutePosition = moneyParent.AbsolutePosition
			local _arg0 = moneyParent.AbsoluteSize / 2
			local targetCenter = _absolutePosition + _arg0
			local fly = TweenService:Create(frame, FLY_TI, {
				Position = UDim2.new(0, targetCenter.X, 0, targetCenter.Y),
			})
			fly.Completed:Connect(function()
				frame:Destroy()
				bank(amount, runGen)
			end)
			fly:Play()
		end)
	end)
	jump:Play()
end
local function init()
	Events.LossRewardEvent.OnClientEvent:Connect(function(amount)
		-- The HUD was hidden during gameplay; bring it back so the money is visible
		-- (GameResultEvent already stopped the held pose and returned the camera).
		InGameUIController:enable()
		task.spawn(function()
			return spawnJumpingText(amount)
		end)
	end)
end
return {
	init = init,
}
