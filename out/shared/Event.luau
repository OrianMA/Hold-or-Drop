-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local DefineEvent = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Utils", "DefineEvent").default
local Events = {}
do
	local _container = Events
	-- Start the menu flow. Args: (cameraPosPart, cameraPivotPart) — both from the
	-- room's MovableModel. The client starts an orbit camera at cameraPosPart that
	-- always looks at cameraPivotPart (see CameraController.StartOrbit).
	local ButtonTriggerEvent = DefineEvent("ButtonTriggerEvent", script)
	_container.ButtonTriggerEvent = ButtonTriggerEvent
	local StartButtonClickedEvent = DefineEvent("StartButtonClickedEvent", script)
	_container.StartButtonClickedEvent = StartButtonClickedEvent
	-- RocketLaunch — client → server
	local ReleaseButtonEvent = DefineEvent("ReleaseButtonEvent", script)
	_container.ReleaseButtonEvent = ReleaseButtonEvent
	local QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script)
	_container.QuitButtonClickedEvent = QuitButtonClickedEvent
	local PerfectParryEvent = DefineEvent("PerfectParryEvent", script)
	_container.PerfectParryEvent = PerfectParryEvent
	-- RocketLaunch — server → client
	local PerfectParryEffectEvent = DefineEvent("PerfectParryEffectEvent", script)
	_container.PerfectParryEffectEvent = PerfectParryEffectEvent
	local ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script)
	_container.ButtonExplodedEvent = ButtonExplodedEvent
	local PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script)
	_container.PlayerKilledEvent = PlayerKilledEvent
	local MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script)
	_container.MultiplierUpdateEvent = MultiplierUpdateEvent
	local RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script)
	_container.RiskUpdateEvent = RiskUpdateEvent
	local GameResultEvent = DefineEvent("GameResultEvent", script)
	_container.GameResultEvent = GameResultEvent
	-- EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	local EndGameStartEvent = DefineEvent("EndGameStartEvent", script)
	_container.EndGameStartEvent = EndGameStartEvent
	-- EndGameButton — client → server (animation finished, server hides the popup)
	local EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script)
	_container.EndGameFinishedEvent = EndGameFinishedEvent
	-- Generic info popup — server tells client to flash text in InGameUI's
	-- InformationTextCanvasGroup. Used e.g. for "Not enough money".
	-- Args: (text: string, color?: Color3).
	local InformationTextEvent = DefineEvent("InformationTextEvent", script)
	_container.InformationTextEvent = InformationTextEvent
	-- Shop — client → server. Player clicked a cash buy button.
	-- Arg: itemId (ShopItemId from shared/ShopConfig). Server validates money,
	-- cap and ownership, then deducts and bumps the level.
	local ShopPurchaseEvent = DefineEvent("ShopPurchaseEvent", script)
	_container.ShopPurchaseEvent = ShopPurchaseEvent
	-- Rebirth — client → server. Player clicked the Rebirth button (no args).
	-- Server validates Money >= rebirthCost(Rebirths), resets cash + the 3 stat
	-- levels, increments Rebirths and re-derives MultRebirth.
	local RebirthEvent = DefineEvent("RebirthEvent", script)
	_container.RebirthEvent = RebirthEvent
	-- Community — client → server (no args). Fired after the client's native
	-- GroupService:PromptJoinAsync returns Joined/AlreadyMember (the player
	-- triggered the CommunityJoinPart). The server re-checks membership (fresh,
	-- via GetGroupsAsync) and grants the ×2 — it never trusts the event blindly.
	local CommunityJoinedEvent = DefineEvent("CommunityJoinedEvent", script)
	_container.CommunityJoinedEvent = CommunityJoinedEvent
end
return {
	Events = Events,
}
