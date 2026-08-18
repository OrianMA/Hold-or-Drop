-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UserInputService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").UserInputService
local informationTextKeys = TS.import(script, script.Parent.Parent, "ClientCheatConfig").informationTextKeys
local InformationText = TS.import(script, script.Parent, "InformationText").InformationText
-- Cheat de dev : J / K / L / M affichent un bandeau de test de chaque rareté.
-- Activé par `informationTextKeys` dans client/ClientCheatConfig.
-- (J-K-L-M et pas U-I-O-P : I et O sont les touches de zoom caméra par défaut
-- de Roblox, elles arrivent donc toujours avec gameProcessed = true.)
local KEYS = { { Enum.KeyCode.J, "Common", "Test Commun" }, { Enum.KeyCode.K, "Rare", "Test Rare" }, { Enum.KeyCode.L, "Epic", "Test Épique" }, { Enum.KeyCode.M, "Legendary", "Test Légendaire" } }
local function init()
	if not informationTextKeys then
		return nil
	end
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return nil
		end
		for _, _binding in KEYS do
			local key = _binding[1]
			local rarity = _binding[2]
			local text = _binding[3]
			if input.KeyCode == key then
				InformationText:show(text, {
					rarity = rarity,
				})
				return nil
			end
		end
	end)
end
return {
	init = init,
}
