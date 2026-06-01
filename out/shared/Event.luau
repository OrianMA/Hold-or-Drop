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
	local PerfectParryEvent = DefineEvent("PerfectParryEvent", script)
	_container.PerfectParryEvent = PerfectParryEvent
	-- ButtonInGame — server → client
	local PerfectParryEffectEvent = DefineEvent("PerfectParryEffectEvent", script)
	_container.PerfectParryEffectEvent = PerfectParryEffectEvent
	local BaseCashEvent = DefineEvent("BaseCashEvent", script)
	_container.BaseCashEvent = BaseCashEvent
	local ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script)
	_container.ButtonExplodedEvent = ButtonExplodedEvent
	local PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script)
	_container.PlayerKilledEvent = PlayerKilledEvent
	local MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script)
	_container.MultiplierUpdateEvent = MultiplierUpdateEvent
	local RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script)
	_container.RiskUpdateEvent = RiskUpdateEvent
	local ProgressUpdateEvent = DefineEvent("ProgressUpdateEvent", script)
	_container.ProgressUpdateEvent = ProgressUpdateEvent
	local GameResultEvent = DefineEvent("GameResultEvent", script)
	_container.GameResultEvent = GameResultEvent
	-- EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	local EndGameStartEvent = DefineEvent("EndGameStartEvent", script)
	_container.EndGameStartEvent = EndGameStartEvent
	-- EndGameButton — client → server (animation finished, server hides the popup)
	local EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script)
	_container.EndGameFinishedEvent = EndGameFinishedEvent
	-- Generic info popup — server tells client to flash text in MainUI's
	-- InformationTextCanvasGroup. Used e.g. for "Not enough money".
	-- Args: (text: string, color?: Color3).
	local InformationTextEvent = DefineEvent("InformationTextEvent", script)
	_container.InformationTextEvent = InformationTextEvent
end
return {
	Events = Events,
}
