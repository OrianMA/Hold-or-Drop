-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher").RocketLauncher
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local TutorialService = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialService").TutorialService
-- Met en scène le run truqué du tutorial. Le jeu de base ne connaît que le handle
-- ci-dessous : il lui demande la deadline d'explosion à chaque tick et le prévient du
-- claim. Tout le scénario (quand geler, quand relancer, quel délai) vit ici.
--
-- La deadline est RÉÉCRITE au claim (explodeAfterClaim) : c'est pourquoi le jeu doit la
-- relire à chaque tour de boucle plutôt que de la lire une fois au décollage.
-- Si le tutorial est coupé (skip) pendant un run truqué sans risque, la fusée volerait
-- pour toujours. On résout alors le run en le faisant exploser peu après.
local ABORT_EXPLODE_DELAY = 2
local activeHandles = {}
local TutorialRunDirector = {
	begin = function(self, player, room, run)
		local startedAt = os.clock()
		-- noRisk (ou rien de précisé) → aucune explosion tant que le script n'en programme
		-- pas une. explodeAt fixe l'instant depuis le décollage.
		local _condition = run.explodeAt
		if _condition == nil then
			_condition = math.huge
		end
		local deadline = _condition
		local frozen = false
		local elapsed = function()
			return os.clock() - startedAt
		end
		-- Le run n'est plus le nôtre si la session a été nettoyée ou a changé de room.
		local stillRunning = function()
			local _result = ButtonSessionService:getSession(player)
			if _result ~= nil then
				_result = _result.room
			end
			return _result == room
		end
		if run.freezeAt ~= nil then
			task.delay(run.freezeAt, function()
				if not stillRunning() then
					return nil
				end
				RocketLauncher:freeze(room)
				frozen = true
				-- Saut d'étape DÉTERMINISTE : on ne dépend pas du timing d'un signal client.
				if run.advanceToOnFreeze ~= nil then
					TutorialService:advanceTo(player, run.advanceToOnFreeze)
				end
			end)
		end
		local _player = player
		activeHandles[_player] = {
			abort = function()
				if frozen then
					RocketLauncher:unfreeze(room)
					frozen = false
				end
				-- Le run doit se terminer tout seul, sinon la fusée reste en l'air.
				if deadline == math.huge then
					deadline = elapsed() + ABORT_EXPLODE_DELAY
				end
			end,
		}
		return {
			explosionAt = function()
				return deadline
			end,
			onClaim = function()
				if run.unfreezeOnClaim == true and frozen then
					RocketLauncher:unfreeze(room)
					frozen = false
				end
				if run.explodeAfterClaim ~= nil then
					deadline = elapsed() + run.explodeAfterClaim
				end
			end,
		}
	end,
	abort = function(self, player)
		local _player = player
		local _result = activeHandles[_player]
		if _result ~= nil then
			_result.abort()
		end
		local _player_1 = player
		activeHandles[_player_1] = nil
	end,
}
-- Le service annonce la fin du tutorial ; le director résout le run en vol. Enregistré à
-- la première charge du module (ButtonInGameModule → TutorialHooks → ici).
TutorialService:setRunAbortHandler(function(player)
	return TutorialRunDirector:abort(player)
end)
return {
	TutorialRunDirector = TutorialRunDirector,
}
