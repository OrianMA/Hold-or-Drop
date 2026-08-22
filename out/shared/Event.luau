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
	-- Claim locks in the current multiplier as a guaranteed win; the rocket keeps
	-- flying (multiplier keeps climbing on screen) until it explodes, then the payout
	-- uses the locked value. Replaces the old ReleaseButtonEvent (instant bank).
	local ClaimButtonEvent = DefineEvent("ClaimButtonEvent", script)
	_container.ClaimButtonEvent = ClaimButtonEvent
	-- RocketLaunch — client → server (no args). Once claimed, the ClaimButton re-arms as
	-- "Go Home": the player ends the run early instead of waiting for the explosion. The
	-- rocket stops, the locked gain is paid exactly like a post-claim explosion, minus the
	-- explosion itself. Only accepted after a claim.
	local GoHomeEvent = DefineEvent("GoHomeEvent", script)
	_container.GoHomeEvent = GoHomeEvent
	local QuitButtonClickedEvent = DefineEvent("QuitButtonClickedEvent", script)
	_container.QuitButtonClickedEvent = QuitButtonClickedEvent
	-- RocketLaunch — client → server. The player's native left/right movement input
	-- (keyboard A/D, mobile thumbstick, gamepad), quantised to -1 (left) / 0 / +1
	-- (right) and sent ONLY when it changes. The server rolls the flying rocket toward
	-- that direction (RocketLauncher.setSteer), tilting its up-axis so it drifts
	-- sideways. Arg: dir (number). Movement never touches the payout multiplier.
	local RocketSteerEvent = DefineEvent("RocketSteerEvent", script)
	_container.RocketSteerEvent = RocketSteerEvent
	-- RocketLaunch — server → client
	-- Server confirms a claim with the authoritative locked multiplier
	-- (Args: multiplier, perfect, critical) so the client shows the exact value that will
	-- be paid out. `perfect` = Perfect Claim: the claim landed inside the last window
	-- before the scheduled explosion, so the multiplier ALREADY includes the ×3 bonus and
	-- the client flashes the red "PERFECT CLAIM" text at the explosion. `critical` =
	-- Critical Claim: a flat 5% roll won at claim time, multiplier ALREADY includes the
	-- ×10, and the client flashes the golden "CRITICAL CLAIM" text right away (see
	-- shared/RocketGameConfig, client/ui/ClaimFlashText).
	local ClaimAcceptedEvent = DefineEvent("ClaimAcceptedEvent", script)
	_container.ClaimAcceptedEvent = ClaimAcceptedEvent
	local ButtonExplodedEvent = DefineEvent("ButtonExplodedEvent", script)
	_container.ButtonExplodedEvent = ButtonExplodedEvent
	local PlayerKilledEvent = DefineEvent("PlayerKilledEvent", script)
	_container.PlayerKilledEvent = PlayerKilledEvent
	local MultiplierUpdateEvent = DefineEvent("MultiplierUpdateEvent", script)
	_container.MultiplierUpdateEvent = MultiplierUpdateEvent
	local GameResultEvent = DefineEvent("GameResultEvent", script)
	_container.GameResultEvent = GameResultEvent
	-- EndGameButton — server → client (starts the post-game animation in ButtonFinishGame)
	local EndGameStartEvent = DefineEvent("EndGameStartEvent", script)
	_container.EndGameStartEvent = EndGameStartEvent
	-- EndGameButton — client → server (animation finished, server hides the popup).
	-- Also fired by LossRewardBehavior once the consolation text lands, so the same
	-- pendingEarned credit path banks a losing-explosion reward.
	local EndGameFinishedEvent = DefineEvent("EndGameFinishedEvent", script)
	_container.EndGameFinishedEvent = EndGameFinishedEvent
	-- EndGameButton — server → client (Arg: earned). Another popup opened while the
	-- payout was pending (typically the player re-triggered the button/rocket during the
	-- 1s release delay, or mid-animation): the finish screen is dropped entirely — no
	-- ButtonFinishGame popup, no HUD restore, the new screen keeps the focus. The client
	-- cancels any running payout animation and shows what is left as a single "+amount"
	-- that jumps then fades on the spot, banking it via EndGameFinishedEvent.
	local EndGamePayoutFlushEvent = DefineEvent("EndGamePayoutFlushEvent", script)
	_container.EndGamePayoutFlushEvent = EndGamePayoutFlushEvent
	-- Losing explosion — server → client (Arg: amount). No ButtonFinishGame popup:
	-- the player gets a flat consolation (baseCash / 3) shown as a single "+amount"
	-- text that jumps then flies into the money HUD (LossRewardBehavior). The client
	-- banks it on arrival by firing EndGameFinishedEvent (shared credit path).
	local LossRewardEvent = DefineEvent("LossRewardEvent", script)
	_container.LossRewardEvent = LossRewardEvent
	-- Generic info popup — server tells client to flash a banner in InGameUI's
	-- InformationTextCanvasGroup. Used e.g. for "Not enough money".
	-- Args: (text: string, options?: InformationTextOptions) — voir
	-- shared/InformationRarity (rarity / color / holdSeconds). Les bandeaux
	-- s'empilent verticalement côté client, plusieurs peuvent coexister.
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
	-- Rebirth — server → client (no args). Fired ONLY on a normal rebirth (Money reset
	-- to 0), never on safe rebirth. Tells the client to drop any in-flight "flying cash"
	-- floating texts (end-game payout chunks + loss-reward text) so nothing lands in the
	-- money HUD after the balance was reset. The matching server pending payout is cleared
	-- via EndGameButtonModule.cancelPending so no money is credited either (FloatingCash).
	local RebirthResetEvent = DefineEvent("RebirthResetEvent", script)
	_container.RebirthResetEvent = RebirthResetEvent
	-- Community — client → server (no args). Fired after the client's native
	-- GroupService:PromptJoinAsync returns Joined/AlreadyMember (the player
	-- triggered the CommunityJoinPart). The server re-checks membership (fresh,
	-- via GetGroupsAsync) and grants the ×2 — it never trusts the event blindly.
	local CommunityJoinedEvent = DefineEvent("CommunityJoinedEvent", script)
	_container.CommunityJoinedEvent = CommunityJoinedEvent
	-- Cheat de dev — client → server (no args). Touche G : replanifie le prochain
	-- événement Mega Rocket dans MEGA_ROCKET_CHEAT_DELAY secondes. Le serveur
	-- n'écoute cet event QUE si CheatConfig.megaRocketCheatKey est vrai — il est
	-- donc totalement inerte en production.
	local MegaRocketCheatEvent = DefineEvent("MegaRocketCheatEvent", script)
	_container.MegaRocketCheatEvent = MegaRocketCheatEvent
	-- Daily reward — client → server (no args). Player clicked the free Claim button.
	-- The server re-derives the streak + the day and never trusts the client.
	local DailyRewardClaimEvent = DefineEvent("DailyRewardClaimEvent", script)
	_container.DailyRewardClaimEvent = DailyRewardClaimEvent
	-- Daily reward — server → client. Args: (amount, multiplier, bonusMultiplier).
	-- Confirms the grant with the authoritative numbers: `amount` is the cash already
	-- credited, `multiplier` the streak multiplier used, `bonusMultiplier` 3 when it
	-- came from the "3X Claim" developer product (1 otherwise).
	local DailyRewardGrantedEvent = DefineEvent("DailyRewardGrantedEvent", script)
	_container.DailyRewardGrantedEvent = DailyRewardGrantedEvent
	-- Cheat de dev — client → server (no args). Touche P : fait avancer la récompense
	-- journalière d'un jour (réarme le claim + rouvre le popup). Le serveur ne
	-- l'écoute que si CheatConfig.dailyRewardCheatKey (§6.25/§9).
	local DailyRewardCheatEvent = DefineEvent("DailyRewardCheatEvent", script)
	_container.DailyRewardCheatEvent = DailyRewardCheatEvent
	-- Quête accomplie — server → client (no args). Signal de PRÉSENTATION seulement :
	-- la récompense est déjà versée et l'état déjà publié par les attributs Q_/QR_
	-- (§6.26). Le client flashe le bandeau Epic "Quest finish" + la pluie d'icônes.
	-- Un event plutôt qu'une lecture d'attribut : au join les attributs arrivent par
	-- réplication, et une quête rechargée EN COOLDOWN déclencherait une fausse pluie.
	local QuestCompletedEvent = DefineEvent("QuestCompletedEvent", script)
	_container.QuestCompletedEvent = QuestCompletedEvent
	-- Boutique ScrollToken (§6.27) — client → server. Arg: itemId (ScrollShopItemId).
	-- Le serveur revalide le prix, le solde et l'unicité : le client ne décide rien.
	local ScrollShopPurchaseEvent = DefineEvent("ScrollShopPurchaseEvent", script)
	_container.ScrollShopPurchaseEvent = ScrollShopPurchaseEvent
	-- Boutique ScrollToken — server → client. Args: (itemId, price). Achat confirmé :
	-- les tokens sont DÉJÀ débités et l'effet appliqué, le client joue l'animation de
	-- dépense + le bandeau de l'objet. Un refus passe par InformationTextEvent.
	local ScrollShopPurchasedEvent = DefineEvent("ScrollShopPurchasedEvent", script)
	_container.ScrollShopPurchasedEvent = ScrollShopPurchasedEvent
	-- Cheat de dev — client → server (no args). Touche U : termine une quête
	-- disponible (récompense + célébration) et crédite QUEST_CHEAT_TOKENS. Le serveur
	-- n'écoute que si CheatConfig.questCheatKey (§9).
	local QuestCheatEvent = DefineEvent("QuestCheatEvent", script)
	_container.QuestCheatEvent = QuestCheatEvent
	-- Tutorial — client → server. Arg: stepId (string). Le client signale que la
	-- condition du step courant est remplie ; le serveur IGNORE l'event si l'id ne
	-- correspond pas au step courant (anti double-avance / event en retard).
	-- L'id spécial "skip" termine le tutorial (bouton TutorialSkip).
	local TutorialAdvanceEvent = DefineEvent("TutorialAdvanceEvent", script)
	_container.TutorialAdvanceEvent = TutorialAdvanceEvent
end
return {
	Events = Events,
}
