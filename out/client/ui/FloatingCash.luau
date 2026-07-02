-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Coordinates cancellation of in-flight "flying cash" floating texts — the end-game
-- payout chunks (EndGameAnimation) and the loss-reward text (LossRewardBehavior).
--
-- On a NORMAL rebirth the money balance is reset to 0 server-side; any floating text
-- still flying toward the money HUD would otherwise land AFTER the reset and add money
-- visually (and, without the server guard, actually). RebirthResetEvent tells us to
-- drop them all: we destroy the in-flight frames and bump a generation counter so any
-- deferred arrival callback that survives the destroy no-ops instead of banking.
--
-- Each animation captures current() when it starts and checks isStale() before banking.
-- Frame names used by the two spawn sites (EndGameAnimation + LossRewardBehavior).
local FLOATING_FRAME_NAMES = { "EndGameFloatingChunk", "EndGameBaseCashFly", "LossRewardFloatingText" }
local generation = 0
local function getInGameUI()
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
local function cancelAll()
	generation += 1
	local screenGui = getInGameUI()
	if not screenGui then
		return nil
	end
	for _, desc in screenGui:GetDescendants() do
		local _name = desc.Name
		if table.find(FLOATING_FRAME_NAMES, _name) ~= nil then
			desc:Destroy()
		end
	end
end
local FloatingCash = {
	current = function(self)
		return generation
	end,
	isStale = function(self, gen)
		return gen ~= generation
	end,
	init = function(self)
		Events.RebirthResetEvent.OnClientEvent:Connect(function()
			return cancelAll()
		end)
	end,
}
return {
	FloatingCash = FloatingCash,
}
