-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local SoundService = _services.SoundService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Son de clic centralisé pour TOUTE l'UI. Au lieu de câbler le son bouton par
-- bouton, on accroche automatiquement chaque GuiButton du PlayerGui : ceux déjà
-- présents au démarrage et ceux ajoutés plus tard (DescendantAdded). Ainsi tout
-- nouveau bouton créé en Studio joue ce son sans aucune ligne de code en plus.
--
-- 100 % client / présentation. Son 2D (personnel), joué via un template
-- préchargé en SoundService — cloné à chaque clic pour autoriser les
-- chevauchements et éviter un fetch CDN au premier clic.
local CLICK_ID = AudioConfig.sfx.uiClick.id
local CLICK_VOLUME = AudioConfig.sfx.uiClick.volume
-- Template persistant : garde l'asset en mémoire dès le démarrage.
local template = (function()
	local sound = Instance.new("Sound")
	sound.Name = "UiClickTemplate"
	sound.SoundId = CLICK_ID
	sound.Volume = CLICK_VOLUME
	sound.Parent = SoundService
	return sound
end)()
local function playClick()
	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
end
-- Évite de connecter deux fois le même bouton (le scan initial et DescendantAdded
-- peuvent se recouper selon l'ordre de chargement du PlayerGui).
local hooked = {}
local function hook(instance)
	if not instance:IsA("GuiButton") then
		return nil
	end
	local _instance = instance
	if hooked[_instance] ~= nil then
		return nil
	end
	local _instance_1 = instance
	hooked[_instance_1] = true
	instance.Activated:Connect(playClick)
end
local function init()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, desc in gui:GetDescendants() do
		hook(desc)
	end
	gui.DescendantAdded:Connect(hook)
end
return {
	init = init,
}
