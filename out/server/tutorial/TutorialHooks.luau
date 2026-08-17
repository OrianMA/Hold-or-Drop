-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local TutorialRunDirector = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialRunDirector").TutorialRunDirector
local TutorialService = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialService").TutorialService
-- LA seule API que le jeu de base appelle. Hors tutorial (ou sur un step sans scénario)
-- tout renvoie undefined : le jeu garde exactement son comportement normal.
local TutorialHooks = {
	beginRun = function(self, player, room)
		local step = TutorialService:getCurrentStep(player)
		if not step or step.run == nil then
			return nil
		end
		return TutorialRunDirector:begin(player, room, step.run)
	end,
}
return {
	TutorialHooks = TutorialHooks,
}
