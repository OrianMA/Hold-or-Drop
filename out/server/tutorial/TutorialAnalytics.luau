-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
local TUTORIAL_STEPS = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "tutorial", "TutorialSteps").TUTORIAL_STEPS
-- Toute la sémantique analytics du tutorial (le jeu de base ne gagne qu'un helper
-- générique, AnalyticsService.funnelStep). Voir le spec tutorial §9.
--
--   Funnel "Tutorial" : un pas à l'ENTRÉE de chaque step → le drop-off entre N et N+1
--   est le taux d'abandon PENDANT le step N. funnelSessionId = le runId persisté, donc
--   un joueur qui revient après un relog reste dans le même funnel.
local FUNNEL = "Tutorial"
-- "Step03" — index 0-based → libellé 1-based zéro-paddé, pour que le dashboard trie
-- les marches dans l'ordre du tutorial et pas dans l'ordre alphabétique.
local function stepLabel(index)
	return string.format("Step%02d", index + 1)
end
local TutorialAnalytics = {
	started = function(self, player, resumed)
		AnalyticsService:custom(player, "TutorialStarted", 1, if resumed then "Resumed" else "Fresh")
	end,
	stepEntered = function(self, player, runId, index, stepId)
		AnalyticsService:funnelStep(player, FUNNEL, runId, index + 1, stepId)
	end,
	stepDone = function(self, player, stepId, seconds, index)
		AnalyticsService:custom(player, "TutorialStepDone", seconds, stepId, stepLabel(index))
	end,
	completed = function(self, player, runId, totalSeconds)
		AnalyticsService:funnelStep(player, FUNNEL, runId, #TUTORIAL_STEPS + 1, "Done")
		AnalyticsService:custom(player, "TutorialCompleted", totalSeconds, "NoSkip", `{#TUTORIAL_STEPS}Steps`)
	end,
	skipped = function(self, player, stepId, seconds, stepsDone)
		AnalyticsService:custom(player, "TutorialSkipped", seconds, stepId, `{stepsDone}Steps`)
	end,
}
return {
	TutorialAnalytics = TutorialAnalytics,
}
