import DefineEvent from "./Utils/DefineEvent";

export namespace Events {
	export const ButtonTriggerEvent = DefineEvent("ButtonTriggerEvent", script);
	export const StartButtonClickedEvent = DefineEvent("StartButtonClickedEvent", script);

	// ButtonInGame — client → server
	export const ReleaseButtonEvent = DefineEvent("ReleaseButtonEvent", script);
	export const QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script);
	export const PerfectParryEvent = DefineEvent("PerfectParryEvent", script);

	// ButtonInGame — server → client
	export const PerfectParryEffectEvent = DefineEvent("PerfectParryEffectEvent", script);
	export const BaseCashEvent = DefineEvent("BaseCashEvent", script);
	export const ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script);
	export const PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script);
	export const MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script);
	export const RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script);
	export const ProgressUpdateEvent = DefineEvent("ProgressUpdateEvent", script);
	export const GameResultEvent = DefineEvent("GameResultEvent", script);
	export const ButtonLevelsEvent = DefineEvent("ButtonLevelsEvent", script);

	// EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	export const EndGameStartEvent = DefineEvent("EndGameStartEvent", script);
	// EndGameButton — client → server (animation finished, server hides the popup)
	export const EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script);

	// Generic info popup — server tells client to flash text in MainUI's
	// InformationTextCanvasGroup. Used e.g. for "Not enough money".
	// Args: (text: string, color?: Color3).
	export const InformationTextEvent = DefineEvent("InformationTextEvent", script);
}
