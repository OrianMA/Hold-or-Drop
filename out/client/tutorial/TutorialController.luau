-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local stepById = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "tutorial", "TutorialSteps").stepById
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
local TutorialSkipButton = TS.import(script, script.Parent, "TutorialSkipButton").TutorialSkipButton
local TutorialTriggers = TS.import(script, script.Parent, "TutorialTriggers").TutorialTriggers
local TutorialArrow = TS.import(script, script.Parent, "TutorialArrow").TutorialArrow
local TutorialTargets = TS.import(script, script.Parent, "TutorialTargets").TutorialTargets
local TutorialFocus = TS.import(script, script.Parent, "TutorialFocus").TutorialFocus
local TutorialGate = TS.import(script, script.Parent, "TutorialGate").TutorialGate
local setTutorialActive = TS.import(script, script.Parent.Parent, "behaviors", "RocketLaunchBehavior").setTutorialActive
-- Orchestre le rendu du tutorial côté client. Le serveur publie l'étape courante dans
-- l'attribut répliqué TutorialStep ("" = terminé) ; ce contrôleur la lit, monte la mise
-- en scène du step, et remonte la complétion via TutorialAdvanceEvent.
local STEP_ATTR = "TutorialStep"
local SKIP_ID = "skip"
local player = Players.LocalPlayer
-- Démontage de la mise en scène du step courant.
local teardown
local function clearStep()
	if teardown then
		teardown()
		teardown = nil
	end
	TutorialArrow:clear()
	TutorialFocus:clear()
	TutorialGate:unlock()
	TutorialUI:hideBanner()
end
local function showStep(step)
	clearStep()
	TutorialUI:ensure()
	TutorialUI:setText(step.text, step.textY)
	-- Pointage. Le monde peut yielder (streaming) → task.spawn, et on vérifie que le
	-- step n'a pas changé entre-temps avant d'afficher quoi que ce soit.
	local target = step.target
	if target.kind == "gui" then
		local gui = TutorialTargets:resolveGui(target.path)
		if gui then
			TutorialArrow:pointAtGui(gui)
			if step.focus ~= nil then
				TutorialFocus:apply(gui, step.focus)
				TutorialGate:lockGui(gui)
			end
		else
			warn(`TutorialController: cible GUI introuvable "{target.path}"`)
		end
	elseif target.kind == "world" then
		local shownFor = step.id
		task.spawn(function()
			local part = TutorialTargets:resolveWorld(target.part)
			local _condition = (player:GetAttribute(STEP_ATTR))
			if _condition == nil then
				_condition = ""
			end
			local currentId = _condition
			if not part or currentId ~= shownFor then
				return nil
			end
			TutorialArrow:pointAtWorld(part)
			TutorialGate:lockPrompts(part)
		end)
	else
		-- Steps sans cible (watch-launch, claim-explode) : rien à pointer, mais tout doit
		-- rester verrouillé. C'est ce qui bloque "Go Home" pendant le step post-claim —
		-- un clic chanceux dans la fenêtre de re-arm sauterait l'explosion que le tutorial
		-- veut montrer — et empêche un claim prématuré avant le gel.
		-- Le bouton Skip est explicitement épargné par lockGui.
		TutorialGate:lockGui(nil)
	end
	-- La complétion est remontée au serveur, qui valide que c'est bien le step courant.
	local stopWatching = TutorialTriggers:watch(step, function()
		Events.TutorialAdvanceEvent:FireServer(step.id)
	end)
	teardown = function()
		return stopWatching()
	end
end
local function render()
	local _condition = (player:GetAttribute(STEP_ATTR))
	if _condition == nil then
		_condition = ""
	end
	local stepId = _condition
	if stepId == "" then
		-- Tutorial terminé : on démonte tout, plus une seule connexion active.
		clearStep()
		setTutorialActive(false)
		TutorialSkipButton:setVisible(false)
		TutorialUI:destroy()
		return nil
	end
	local step = stepById(stepId)
	if not step then
		-- Id inconnu : on ne sait pas quoi afficher, mais le tutorial est toujours en cours
		-- côté serveur (attribut non vide). On démonte juste la présentation du step
		-- précédent — même teardown que pour l'attribut vide, moins TutorialUI.destroy() —
		-- pour ne pas laisser le texte/highlight d'un ancien step à l'écran.
		warn(`TutorialController: step inconnu "{stepId}"`)
		clearStep()
		TutorialSkipButton:setVisible(false)
		return nil
	end
	setTutorialActive(true)
	TutorialSkipButton:setVisible(true)
	showStep(step)
end
local function init()
	TutorialSkipButton:init(function()
		return Events.TutorialAdvanceEvent:FireServer(SKIP_ID)
	end)
	-- Masqué par défaut : un joueur qui a déjà fini ne doit jamais le voir.
	TutorialSkipButton:setVisible(false)
	player:GetAttributeChangedSignal(STEP_ATTR):Connect(render)
	-- L'attribut peut déjà être arrivé avant l'init du client.
	render()
end
return {
	init = init,
}
