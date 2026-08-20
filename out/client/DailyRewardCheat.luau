-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UserInputService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").UserInputService
local dailyRewardKey = TS.import(script, script.Parent, "ClientCheatConfig").dailyRewardKey
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Cheat de dev : la touche P fait "avancer d'un jour" la récompense journalière
-- (§6.25) — le serveur recule le dernier claim d'une journée, ce qui réarme la
-- récompense, fait monter la streak au prochain claim et rouvre le popup.
-- Permet de rejouer l'animation et de voir le compteur de jours grimper sans
-- attendre minuit UTC.
--
-- Activé par `dailyRewardKey` (client/ClientCheatConfig) ET par
-- `dailyRewardCheatKey` côté serveur — sans le second, l'event est ignoré.
--
-- P et pas une touche du bloc WASD/espace : le déplacement natif pilote la fusée
-- pendant un vol (voir RocketSteerController).
--
-- ⚠️ Le projet évite d'habitude U/I/O/P (I et O sont le zoom caméra par défaut de
-- Roblox et arrivent avec `gameProcessed = true`). P est demandé explicitement, donc
-- on ne filtre PAS sur `gameProcessed` — sinon la touche pourrait rester muette si
-- Roblox la marque comme traitée. On écarte seulement le cas qui compte vraiment
-- ici : le joueur est en train d'écrire dans un champ de texte (chat).
local function init()
	if not dailyRewardKey then
		return nil
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.P then
			return nil
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return nil
		end
		Events.DailyRewardCheatEvent:FireServer()
	end)
end
return {
	init = init,
}
