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
return {
	informationTextKeys = informationTextKeys,
}
