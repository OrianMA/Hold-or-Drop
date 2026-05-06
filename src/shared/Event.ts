import DefineEvent from "./Utils/DefineEvent";

export namespace Events {
	export const ButtonTriggerEvent = DefineEvent("ButtonTriggerEvent", script);
	export const StartButtonClickedEvent = DefineEvent("StartButtonClickedEvent", script);

	// ButtonInGame — client → server
	export const ReleaseButtonEvent = DefineEvent("ReleaseButtonEvent", script);

	// ButtonInGame — server → client
	export const ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script);
	export const MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script);
	export const RiskUpdateEvent = DefineEvent("RiskUpdateEvent", script);
	export const GameResultEvent = DefineEvent("GameResultEvent", script);
}
