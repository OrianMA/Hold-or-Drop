import DefineEvent from "./Utils/DefineEvent";

export namespace Events {
	// Start the menu flow. Args: (cameraPosPart, cameraPivotPart) — both from the
	// room's MovableModel. The client starts an orbit camera at cameraPosPart that
	// always looks at cameraPivotPart (see CameraController.StartOrbit).
	export const ButtonTriggerEvent = DefineEvent("ButtonTriggerEvent", script);
	export const StartButtonClickedEvent = DefineEvent("StartButtonClickedEvent", script);

	// RocketLaunch — client → server
	// Claim locks in the current multiplier as a guaranteed win; the rocket keeps
	// flying (multiplier keeps climbing on screen) until it explodes, then the payout
	// uses the locked value. Replaces the old ReleaseButtonEvent (instant bank).
	export const ClaimButtonEvent = DefineEvent("ClaimButtonEvent", script);
	export const QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script);
	export const PerfectParryEvent = DefineEvent("PerfectParryEvent", script);

	// RocketLaunch — server → client
	// Server confirms a claim with the authoritative locked multiplier (Arg: multiplier)
	// so the client shows the exact value that will be paid out.
	export const ClaimAcceptedEvent = DefineEvent("ClaimAcceptedEvent", script);
	export const PerfectParryEffectEvent = DefineEvent("PerfectParryEffectEvent", script);
	export const ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script);
	export const PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script);
	export const MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script);
	export const RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script);
	export const GameResultEvent = DefineEvent("GameResultEvent", script);

	// EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	export const EndGameStartEvent = DefineEvent("EndGameStartEvent", script);
	// EndGameButton — client → server (animation finished, server hides the popup).
	// Also fired by LossRewardBehavior once the consolation text lands, so the same
	// pendingEarned credit path banks a losing-explosion reward.
	export const EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script);

	// Losing explosion — server → client (Arg: amount). No ButtonFinishGame popup:
	// the player gets a flat consolation (baseCash / 3) shown as a single "+amount"
	// text that jumps then flies into the money HUD (LossRewardBehavior). The client
	// banks it on arrival by firing EndGameFinishedEvent (shared credit path).
	export const LossRewardEvent = DefineEvent("LossRewardEvent", script);

	// Generic info popup — server tells client to flash text in InGameUI's
	// InformationTextCanvasGroup. Used e.g. for "Not enough money".
	// Args: (text: string, color?: Color3).
	export const InformationTextEvent = DefineEvent("InformationTextEvent", script);

	// Shop — client → server. Player clicked a cash buy button.
	// Arg: itemId (ShopItemId from shared/ShopConfig). Server validates money,
	// cap and ownership, then deducts and bumps the level.
	export const ShopPurchaseEvent = DefineEvent("ShopPurchaseEvent", script);

	// Rebirth — client → server. Player clicked the Rebirth button (no args).
	// Server validates Money >= rebirthCost(Rebirths), resets cash + the 3 stat
	// levels, increments Rebirths and re-derives MultRebirth.
	export const RebirthEvent = DefineEvent("RebirthEvent", script);

	// Community — client → server (no args). Fired after the client's native
	// GroupService:PromptJoinAsync returns Joined/AlreadyMember (the player
	// triggered the CommunityJoinPart). The server re-checks membership (fresh,
	// via GetGroupsAsync) and grants the ×2 — it never trusts the event blindly.
	export const CommunityJoinedEvent = DefineEvent("CommunityJoinedEvent", script);
}
