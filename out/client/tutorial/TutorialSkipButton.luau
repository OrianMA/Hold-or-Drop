-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
-- Le bouton Skip est AUTHORÉ DANS STUDIO (visuel maison) — le code ne fait que
-- l'allumer/l'éteindre et écouter son clic. Hiérarchie attendue :
--   InGameUI/TutorialSkip (Frame)  ← visibilité pilotée ici
--     └── TutorialSkipFrame/TextButton
-- Résolu par NOM en recherche récursive, pour que le frame puisse être déplacé dans
-- Studio sans toucher au code. TutorialSkip est un frère du HUD (et non un enfant) :
-- il survit donc au masquage du HUD pendant un run.
local ROOT_NAME = "TutorialSkip"
local BUTTON_NAME = "TextButton"
local root
local connected = false
-- setVisible() appelle findRoot() à chaque step : si le frame Studio est absent, on ne
-- veut avertir qu'une fois, pas spammer l'output à chaque changement d'étape.
local warnedMissing = false
local function findRoot()
	if root and root.Parent ~= nil then
		return root
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local found = gui:FindFirstChild(ROOT_NAME, true)
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("Frame")
	end
	root = if _result then found else nil
	if not root and not warnedMissing then
		warn(`TutorialSkipButton: {ROOT_NAME} introuvable sous PlayerGui`)
		warnedMissing = true
	end
	return root
end
local TutorialSkipButton = {
	init = function(self, onSkip)
		local frame = findRoot()
		if not frame or connected then
			return nil
		end
		local button = frame:FindFirstChild(BUTTON_NAME, true)
		local _result = button
		if _result ~= nil then
			_result = _result:IsA("GuiButton")
		end
		if not _result then
			warn(`TutorialSkipButton: aucun {BUTTON_NAME} sous {ROOT_NAME}`)
			return nil
		end
		button.Activated:Connect(function()
			return onSkip()
		end)
		connected = true
	end,
	setVisible = function(self, visible)
		local frame = findRoot()
		if frame then
			frame.Visible = visible
		end
	end,
}
return {
	TutorialSkipButton = TutorialSkipButton,
}
