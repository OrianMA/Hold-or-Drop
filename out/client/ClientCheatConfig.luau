-- Compiled with roblox-ts v3.0.0
-- ── Cheats CLIENT ─────────────────────────────────────────────────────────────
-- Pendant client de server/modules/CheatConfig : les modules client ne peuvent
-- pas importer ServerScriptService, donc les cheats qui pilotent du code client
-- vivent ici.
-- Penser à tout remettre à false avant de publier.
-- Touches de test des bandeaux InformationText (client/ui/InformationTextTest) :
--   J = Common   K = Rare   L = Epic   M = Legendary
-- Appuyer plusieurs fois d'affilée pour vérifier l'empilement vertical.
local informationTextKeys = true
-- Touche G (client/MegaRocketCheat) : demande au serveur de ramener le compte à
-- rebours de la Mega Rocket à 3 s. Le serveur a son propre garde
-- (server/modules/CheatConfig.megaRocketCheatKey) — les deux doivent être vrais.
local megaRocketKey = true
-- Touche P (client/DailyRewardCheat) : fait avancer la récompense journalière d'un
-- jour (le dernier claim est reculé d'une journée), ce qui la réarme et rouvre le
-- popup — de quoi rejouer l'animation et voir la streak monter sans attendre 24 h.
-- Le serveur a son propre garde (server/modules/CheatConfig.dailyRewardCheatKey) —
-- les deux doivent être vrais.
local dailyRewardKey = true
-- Touche U (client/QuestCheat) : termine une quête à la demande et crédite 100K
-- ScrollToken. Le serveur a son propre garde
-- (server/modules/CheatConfig.questCheatKey) — les deux doivent être vrais.
local questFinishKey = true
return {
	informationTextKeys = informationTextKeys,
	megaRocketKey = megaRocketKey,
	dailyRewardKey = dailyRewardKey,
	questFinishKey = questFinishKey,
}
