-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local MULTIPLIER_STAGES = { {
	multiplicatorAdded = 1,
	duration = 5,
}, {
	multiplicatorAdded = 2,
	duration = 4,
}, {
	multiplicatorAdded = 3,
	duration = 3,
}, {
	multiplicatorAdded = 5,
	duration = 3,
}, {
	multiplicatorAdded = 10,
	duration = 3,
} }
local MAX_RISK = 0.8
local TICK_RATE = 0.5
local LOOSE_WIN_MULTIPLIER = 0.3
-- Sum of all finite stage durations — defines the full length of the sine curve
local TOTAL_DURATION = 0
for _, stage in MULTIPLIER_STAGES do
	TOTAL_DURATION += stage.duration
end
-- EaseInQuad: risk starts near 0 and accelerates — reaches MAX_RISK at TOTAL_DURATION seconds
-- After that, risk stays capped at MAX_RISK
local function getRisk(timeHeld)
	local t = math.min(timeHeld / TOTAL_DURATION, 1)
	return MAX_RISK * (t * t)
end
-- Single exit point for all outcomes: release, explosion, and quit from ButtonMenu
local function endButtonGame(player)
	ButtonSessionService:cleanup(player)
	UiService:HideCurrent(player)
end
local function startButtonGame(player, session)
	local _binding = session
	local baseCash = _binding.baseCash
	local currentMultiplier = 1
	local isActive = true
	Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
	Events.RiskUpdateEvent:FireClient(player, 0)
	local releaseConn
	releaseConn = Events.ReleaseButtonEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive then
			return nil
		end
		isActive = false
		releaseConn:Disconnect()
		local earned = baseCash * currentMultiplier
		Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
		endButtonGame(player)
	end)
	task.spawn(function()
		local lastIndex = #MULTIPLIER_STAGES - 1
		local stageIndex = 0
		local timeHeld = 0
		while isActive do
			local stage = MULTIPLIER_STAGES[stageIndex + 1]
			local isLastStage = stageIndex == lastIndex
			local timeInStage = 0
			local nextMultiplierTick = 1
			local advanceStage = false
			while isActive do
				task.wait(TICK_RATE)
				if not isActive then
					break
				end
				timeInStage += TICK_RATE
				timeHeld += TICK_RATE
				-- +multiplicatorAdded to the multiplier once per elapsed second
				while timeInStage >= nextMultiplierTick do
					currentMultiplier += stage.multiplicatorAdded
					Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
					nextMultiplierTick += 1
				end
				-- Risk follows a sine curve over the total stage duration
				local risk = getRisk(timeHeld)
				Events.RiskUpdateEvent:FireClient(player, risk)
				-- Explosion check
				if math.random() < risk then
					isActive = false
					releaseConn:Disconnect()
					local earned = math.floor(baseCash * currentMultiplier * LOOSE_WIN_MULTIPLIER)
					Events.ButtonExplodedEvent:FireClient(player)
					task.wait(0.5)
					Events.GameResultEvent:FireClient(player, true, earned, currentMultiplier)
					endButtonGame(player)
					return nil
				end
				if not isLastStage and timeInStage >= stage.duration then
					advanceStage = true
					break
				end
			end
			if not advanceStage then
				break
			end
			stageIndex += 1
		end
	end)
end
return {
	endButtonGame = endButtonGame,
	startButtonGame = startButtonGame,
}
