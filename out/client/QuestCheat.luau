-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UserInputService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").UserInputService
local questFinishKey = TS.import(script, script.Parent, "ClientCheatConfig").questFinishKey
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Cheat de dev : la touche U termine une quête disponible (récompense, bandeau Epic
-- et pluie d'icônes compris) et crédite 100K ScrollToken, de quoi tester la boutique
-- (§6.27) sans farmer.
--
-- Activé par `questFinishKey` (client/ClientCheatConfig) ET par `questCheatKey` côté
-- serveur — sans le second, l'event est ignoré.
--
-- ⚠️ Le projet évite d'habitude U/I/O/P (I et O sont le zoom caméra par défaut de
-- Roblox et arrivent avec `gameProcessed = true`). U est demandé explicitement, donc
-- on ne filtre PAS sur `gameProcessed` — même raisonnement que la touche P du daily
-- (client/DailyRewardCheat) : on écarte seulement le cas qui compte vraiment, le
-- joueur en train d'écrire dans un champ de texte.
local function init()
	if not questFinishKey then
		return nil
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.U then
			return nil
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return nil
		end
		Events.QuestCheatEvent:FireServer()
	end)
end
return {
	init = init,
}
