-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Workspace = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Workspace
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
-- Verrouillage des interactions hors-scope pendant un step. 100 % client : c'est de
-- l'UX, pas de la sécurité (le tutorial ne donne rien de plus que le jeu normal, et le
-- serveur valide de toute façon chaque action).
--
-- Division des responsabilités avec TutorialFocus : le dim MONTRE (assombrit, purement
-- visuel, Active = false), TutorialGate BLOQUE (Interactable = false sur tout GuiButton
-- hors cible/Skip). C'est l'UNIQUE mécanisme de blocage — ne pas réintroduire de frame
-- "Active = true" dans TutorialFocus pour ça, ça repasserait au-dessus du bouton Skip
-- (TutorialUI est à DisplayOrder 100, au-dessus de InGameUI) et le rendrait injoignable.
--
-- L'état d'origine de chaque instance touchée est mémorisé et restauré — jamais de
-- valeur "par défaut" réécrite à l'aveugle.
local lockedButtons = {}
local lockedPrompts = {}
local TutorialGate = {
	lockGui = function(self, target)
		local root = TutorialUI:getInGameUI()
		if not root then
			return nil
		end
		for _, descendant in root:GetDescendants() do
			if not descendant:IsA("GuiButton") then
				continue
			end
			local isTarget = target ~= nil and (descendant == target or descendant:IsDescendantOf(target))
			-- Le bouton Skip doit rester cliquable en permanence.
			local isSkip = descendant:FindFirstAncestor("TutorialSkip") ~= nil
			-- Idem pour le popup Daily Rewards : il s'ouvre au lancement même si le
			-- tutorial n'est pas fini (le tutorial est masqué le temps du popup, voir
			-- TutorialUI.setSuppressed), ses boutons doivent donc rester cliquables.
			local isDaily = descendant:FindFirstAncestor("DailyRewards") ~= nil
			if isTarget or isSkip or isDaily then
				continue
			end
			if not (lockedButtons[descendant] ~= nil) then
				local _interactable = descendant.Interactable
				lockedButtons[descendant] = _interactable
			end
			descendant.Interactable = false
		end
	end,
	lockPrompts = function(self, except)
		for _, descendant in Workspace:GetDescendants() do
			if not descendant:IsA("ProximityPrompt") then
				continue
			end
			if except ~= nil and descendant.Parent == except then
				continue
			end
			if not descendant.Enabled then
				continue
			end
			if not (lockedPrompts[descendant] ~= nil) then
				local _enabled = descendant.Enabled
				lockedPrompts[descendant] = _enabled
			end
			descendant.Enabled = false
		end
	end,
	unlock = function(self)
		for button, interactable in lockedButtons do
			if button.Parent ~= nil then
				button.Interactable = interactable
			end
		end
		table.clear(lockedButtons)
		for prompt, enabled in lockedPrompts do
			if prompt.Parent ~= nil then
				prompt.Enabled = enabled
			end
		end
		table.clear(lockedPrompts)
	end,
}
return {
	TutorialGate = TutorialGate,
}
