-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local UserInputService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").UserInputService
local megaRocketKey = TS.import(script, script.Parent, "ClientCheatConfig").megaRocketKey
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
-- Cheat de dev : la touche G ramène le compte à rebours de la Mega Rocket (§6.24)
-- à 3 s, pour déclencher l'événement à la demande sans attendre les 6 minutes.
-- Activé par `megaRocketKey` (client/ClientCheatConfig) ET par
-- `megaRocketCheatKey` côté serveur — sans le second, l'event est ignoré.
--
-- (G et pas une touche du bloc WASD/espace : le déplacement natif pilote la fusée
-- pendant un vol, voir RocketSteerController.)
local function init()
	if not megaRocketKey then
		return nil
	end
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return nil
		end
		if input.KeyCode ~= Enum.KeyCode.G then
			return nil
		end
		Events.MegaRocketCheatEvent:FireServer()
	end)
end
return {
	init = init,
}
