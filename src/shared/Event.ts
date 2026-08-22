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
	// RocketLaunch — client → server (no args). Once claimed, the ClaimButton re-arms as
	// "Go Home": the player ends the run early instead of waiting for the explosion. The
	// rocket stops, the locked gain is paid exactly like a post-claim explosion, minus the
	// explosion itself. Only accepted after a claim.
	export const GoHomeEvent = DefineEvent("GoHomeEvent", script);
	export const QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script);

	// RocketLaunch — client → server. The player's native left/right movement input
	// (keyboard A/D, mobile thumbstick, gamepad), quantised to -1 (left) / 0 / +1
	// (right) and sent ONLY when it changes. The server rolls the flying rocket toward
	// that direction (RocketLauncher.setSteer), tilting its up-axis so it drifts
	// sideways. Arg: dir (number). Movement never touches the payout multiplier.
	export const RocketSteerEvent = DefineEvent("RocketSteerEvent", script);

	// RocketLaunch — server → client
	// Server confirms a claim with the authoritative locked multiplier
	// (Args: multiplier, perfect, critical) so the client shows the exact value that will
	// be paid out. `perfect` = Perfect Claim: the claim landed inside the last window
	// before the scheduled explosion, so the multiplier ALREADY includes the ×3 bonus and
	// the client flashes the red "PERFECT CLAIM" text at the explosion. `critical` =
	// Critical Claim: a flat 5% roll won at claim time, multiplier ALREADY includes the
	// ×10, and the client flashes the golden "CRITICAL CLAIM" text right away (see
	// shared/RocketGameConfig, client/ui/ClaimFlashText).
	export const ClaimAcceptedEvent = DefineEvent("ClaimAcceptedEvent", script);
	export const ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script);
	export const PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script);
	export const MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script);
	export const GameResultEvent = DefineEvent("GameResultEvent", script);

	// EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	export const EndGameStartEvent = DefineEvent("EndGameStartEvent", script);
	// EndGameButton — client → server (animation finished, server hides the popup).
	// Also fired by LossRewardBehavior once the consolation text lands, so the same
	// pendingEarned credit path banks a losing-explosion reward.
	export const EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script);

	// EndGameButton — server → client (Arg: earned). Another popup opened while the
	// payout was pending (typically the player re-triggered the button/rocket during the
	// 1s release delay, or mid-animation): the finish screen is dropped entirely — no
	// ButtonFinishGame popup, no HUD restore, the new screen keeps the focus. The client
	// cancels any running payout animation and shows what is left as a single "+amount"
	// that jumps then fades on the spot, banking it via EndGameFinishedEvent.
	export const EndGamePayoutFlushEvent = DefineEvent("EndGamePayoutFlushEvent", script);

	// Losing explosion — server → client (Arg: amount). No ButtonFinishGame popup:
	// the player gets a flat consolation (baseCash / 3) shown as a single "+amount"
	// text that jumps then flies into the money HUD (LossRewardBehavior). The client
	// banks it on arrival by firing EndGameFinishedEvent (shared credit path).
	export const LossRewardEvent = DefineEvent("LossRewardEvent", script);

	// Generic info popup — server tells client to flash a banner in InGameUI's
	// InformationTextCanvasGroup. Used e.g. for "Not enough money".
	// Args: (text: string, options?: InformationTextOptions) — voir
	// shared/InformationRarity (rarity / color / holdSeconds). Les bandeaux
	// s'empilent verticalement côté client, plusieurs peuvent coexister.
	export const InformationTextEvent = DefineEvent("InformationTextEvent", script);

	// Shop — client → server. Player clicked a cash buy button.
	// Arg: itemId (ShopItemId from shared/ShopConfig). Server validates money,
	// cap and ownership, then deducts and bumps the level.
	export const ShopPurchaseEvent = DefineEvent("ShopPurchaseEvent", script);

	// Rebirth — client → server. Player clicked the Rebirth button (no args).
	// Server validates Money >= rebirthCost(Rebirths), resets cash + the 3 stat
	// levels, increments Rebirths and re-derives MultRebirth.
	export const RebirthEvent = DefineEvent("RebirthEvent", script);

	// Rebirth — server → client (no args). Fired ONLY on a normal rebirth (Money reset
	// to 0), never on safe rebirth. Tells the client to drop any in-flight "flying cash"
	// floating texts (end-game payout chunks + loss-reward text) so nothing lands in the
	// money HUD after the balance was reset. The matching server pending payout is cleared
	// via EndGameButtonModule.cancelPending so no money is credited either (FloatingCash).
	export const RebirthResetEvent = DefineEvent("RebirthResetEvent", script);

	// Community — client → server (no args). Fired after the client's native
	// GroupService:PromptJoinAsync returns Joined/AlreadyMember (the player
	// triggered the CommunityJoinPart). The server re-checks membership (fresh,
	// via GetGroupsAsync) and grants the ×2 — it never trusts the event blindly.
	export const CommunityJoinedEvent = DefineEvent("CommunityJoinedEvent", script);

	// Cheat de dev — client → server (no args). Touche G : replanifie le prochain
	// événement Mega Rocket dans MEGA_ROCKET_CHEAT_DELAY secondes. Le serveur
	// n'écoute cet event QUE si CheatConfig.megaRocketCheatKey est vrai — il est
	// donc totalement inerte en production.
	export const MegaRocketCheatEvent = DefineEvent("MegaRocketCheatEvent", script);

	// Daily reward — client → server (no args). Player clicked the free Claim button.
	// The server re-derives the streak + the day and never trusts the client.
	export const DailyRewardClaimEvent = DefineEvent("DailyRewardClaimEvent", script);

	// Daily reward — server → client. Args: (amount, multiplier, bonusMultiplier).
	// Confirms the grant with the authoritative numbers: `amount` is the cash already
	// credited, `multiplier` the streak multiplier used, `bonusMultiplier` 3 when it
	// came from the "3X Claim" developer product (1 otherwise).
	export const DailyRewardGrantedEvent = DefineEvent("DailyRewardGrantedEvent", script);

	// Cheat de dev — client → server (no args). Touche P : fait avancer la récompense
	// journalière d'un jour (réarme le claim + rouvre le popup). Le serveur ne
	// l'écoute que si CheatConfig.dailyRewardCheatKey (§6.25/§9).
	export const DailyRewardCheatEvent = DefineEvent("DailyRewardCheatEvent", script);

	// Quête accomplie — server → client (no args). Signal de PRÉSENTATION seulement :
	// la récompense est déjà versée et l'état déjà publié par les attributs Q_/QR_
	// (§6.26). Le client flashe le bandeau Epic "Quest finish" + la pluie d'icônes.
	// Un event plutôt qu'une lecture d'attribut : au join les attributs arrivent par
	// réplication, et une quête rechargée EN COOLDOWN déclencherait une fausse pluie.
	export const QuestCompletedEvent = DefineEvent("QuestCompletedEvent", script);

	// Boutique ScrollToken (§6.27) — client → server. Arg: itemId (ScrollShopItemId).
	// Le serveur revalide le prix, le solde et l'unicité : le client ne décide rien.
	export const ScrollShopPurchaseEvent = DefineEvent("ScrollShopPurchaseEvent", script);

	// Boutique ScrollToken — server → client. Args: (itemId, price). Achat confirmé :
	// les tokens sont DÉJÀ débités et l'effet appliqué, le client joue l'animation de
	// dépense + le bandeau de l'objet. Un refus passe par InformationTextEvent.
	export const ScrollShopPurchasedEvent = DefineEvent("ScrollShopPurchasedEvent", script);

	// Cheat de dev — client → server (no args). Touche U : termine une quête
	// disponible (récompense + célébration) et crédite QUEST_CHEAT_TOKENS. Le serveur
	// n'écoute que si CheatConfig.questCheatKey (§9).
	export const QuestCheatEvent = DefineEvent("QuestCheatEvent", script);

	// Tutorial — client → server. Arg: stepId (string). Le client signale que la
	// condition du step courant est remplie ; le serveur IGNORE l'event si l'id ne
	// correspond pas au step courant (anti double-avance / event en retard).
	// L'id spécial "skip" termine le tutorial (bouton TutorialSkip).
	export const TutorialAdvanceEvent = DefineEvent("TutorialAdvanceEvent", script);
}
