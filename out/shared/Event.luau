-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local DefineEvent = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Utils", "DefineEvent").default
local Events = {}
do
	local _container = Events
	local ButtonTriggerEvent = DefineEvent("ButtonTriggerEvent", script)
	_container.ButtonTriggerEvent = ButtonTriggerEvent
	local StartButtonClickedEvent = DefineEvent("StartButtonClickedEvent", script)
	_container.StartButtonClickedEvent = StartButtonClickedEvent
	-- ButtonInGame — client → server
	local ReleaseButtonEvent = DefineEvent("ReleaseButtonEvent", script)
	_container.ReleaseButtonEvent = ReleaseButtonEvent
	local QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script)
	_container.QuitButtonClickedEvent = QuitButtonClickedEvent
	-- ButtonInGame — server → client
	local ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script)
	_container.ButtonExplodedEvent = ButtonExplodedEvent
	local MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script)
	_container.MultiplierUpdateEvent = MultiplierUpdateEvent
	local RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script)
	_container.RiskUpdateEvent = RiskUpdateEvent
	local ProgressUpdateEvent = DefineEvent("ProgressUpdateEvent", script)
	_container.ProgressUpdateEvent = ProgressUpdateEvent
	local GameResultEvent = DefineEvent("GameResultEvent", script)
	_container.GameResultEvent = GameResultEvent
end
return {
	Events = Events,
}
