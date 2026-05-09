-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local CameraController = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "CameraController").CameraController
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
-- UI refs — assigned on first setup(), never change after
local releaseButton
local baseCashText
local multiplierLabel
local progressionIndicator
local buttonOriginalSize
-- Per-game state
local isGameActive = false
local released = false
local multiplierTextSize = 0
local spaceConn
local activatedConn
local SIZE_GROWTH_PER_UPDATE = 3
local elasticTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local shrinkTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.In)
local fillTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local function endInput()
	isGameActive = false
	released = true
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	spaceConn = nil
	if releaseButton then
		releaseButton.Active = false
		local tween = TweenService:Create(releaseButton, shrinkTweenInfo, {
			Size = UDim2.new(0, 0, 0, 0),
		})
		tween:Play()
		tween.Completed:Wait()
		releaseButton.Visible = false
	end
end
-- Called once at startup — all event listeners live here, gated by isGameActive
local function init()
	Events.GameResultEvent.OnClientEvent:Connect(function(exploded, cashEarned, multiplier)
		CameraController.BringBackPlayerCamera()
		print(`Game over — exploded: {exploded} | cash: {cashEarned} | {multiplier}x`)
	end)
	Events.BaseCashEvent.OnClientEvent:Connect(function(baseCash)
		if not isGameActive or not baseCashText then
			return nil
		end
		baseCashText.Text = `${baseCash}`
	end)
	Events.MultiplierUpdateEvent.OnClientEvent:Connect(function(multiplier)
		if not isGameActive or not multiplierLabel then
			return nil
		end
		multiplierLabel.Text = `{multiplier}x`
		multiplierTextSize += SIZE_GROWTH_PER_UPDATE
		TweenService:Create(multiplierLabel, elasticTweenInfo, {
			TextSize = multiplierTextSize,
		}):Play()
	end)
	Events.ProgressUpdateEvent.OnClientEvent:Connect(function(progress)
		if not isGameActive or not progressionIndicator then
			return nil
		end
		TweenService:Create(progressionIndicator, fillTweenInfo, {
			Position = UDim2.new(progress, 0, 0.5, 0),
		}):Play()
	end)
	Events.ButtonExplodedEvent.OnClientEvent:Connect(function()
		if not isGameActive then
			return nil
		end
		print("Button exploded!")
		-- Grace period: player can still release to cancel the explosion
		task.delay(0.2, function()
			if not released then
				endInput()
			end
		end)
	end)
end
-- Called each time the player starts a new game (after clicking StartButton)
local function setup(mainUI)
	local popup = mainUI:WaitForChild("ButtonInGame")
	releaseButton = popup:WaitForChild("ReleaseButton")
	baseCashText = popup:WaitForChild("BaseCashText")
	local sliderParent = popup:WaitForChild("Slider")
	multiplierLabel = sliderParent:WaitForChild("MultiplierLabel")
	local progressBarParent = sliderParent:WaitForChild("ProgressBar")
	progressionIndicator = progressBarParent:WaitForChild("ProgressionIndicator")
	-- Save original button size on first run so we can restore it each game
	if not buttonOriginalSize then
		buttonOriginalSize = releaseButton.Size
	end
	-- Reset per-game state
	isGameActive = true
	released = false
	multiplierTextSize = multiplierLabel.TextSize
	-- Restore button to full size and re-enable it
	releaseButton.Size = buttonOriginalSize
	releaseButton.Active = true
	releaseButton.Visible = true
	print(releaseButton.Activated)
	-- Reset UI
	multiplierLabel.Text = "1x"
	progressionIndicator.Position = UDim2.new(0, 0, 0.5, 0)
	-- Clean up any leftover connections from a previous game
	local _result = spaceConn
	if _result ~= nil then
		_result:Disconnect()
	end
	local _result_1 = activatedConn
	if _result_1 ~= nil then
		_result_1:Disconnect()
	end
	local fireRelease = function()
		if not isGameActive or released then
			return nil
		end
		endInput()
		Events.ReleaseButtonEvent:FireServer()
	end
	activatedConn = releaseButton.Activated:Connect(fireRelease)
	spaceConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isGameActive or released then
			return nil
		end
		if input.KeyCode == Enum.KeyCode.Space then
			fireRelease()
		end
	end)
end
return {
	init = init,
	setup = setup,
}
