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
return {
	informationTextKeys = informationTextKeys,
	megaRocketKey = megaRocketKey,
}
