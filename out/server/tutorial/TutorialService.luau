-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local HttpService = _services.HttpService
local Players = _services.Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _TutorialSteps = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "tutorial", "TutorialSteps")
local TUTORIAL_STEPS = _TutorialSteps.TUTORIAL_STEPS
local firstStepId = _TutorialSteps.firstStepId
local stepById = _TutorialSteps.stepById
local stepIndexById = _TutorialSteps.stepIndexById
local forceTutorial = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").forceTutorial
-- État du tutorial par joueur. Le SERVEUR est la source de vérité de l'étape courante :
-- il la publie via l'attribut répliqué `TutorialStep` (le client ne fait que lire et
-- rendre), la persiste dans son propre store et l'avance sur signal client.
--
-- Store dédié PlayerTutorial_v1 : aucune migration ni risque sur PlayerData/Progression,
-- et retirer le tutorial ne laisse qu'un store orphelin inoffensif.
local STEP_ATTR = "TutorialStep"
local STORE_NAME = "PlayerTutorial_v1"
local SKIP_ID = "skip"
local dataStore = DataStoreService:GetDataStore(STORE_NAME)
local states = {}
-- Seuls les joueurs dont le load a réussi sont sauvegardables — un échec transitoire
-- ne doit jamais écraser une progression existante.
local loadedPlayers = {}
local function keyFor(player)
	return `Player_{player.UserId}`
end
local function newRunId()
	local ok, id = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	return if ok then id else `{tick()}`
end
local function freshSave()
	return {
		step = firstStepId(),
		done = false,
		runId = newRunId(),
		elapsed = 0,
	}
end
local function loadSave(player)
	local success, result = pcall(function()
		return dataStore:GetAsync(keyFor(player))
	end)
	if not success then
		warn(`TutorialService: failed to load {player.Name}: {result}`)
		return nil
	end
	if result == nil or not (type(result) == "table") then
		return freshSave()
	end
	local loaded = result
	local save = freshSave()
	local _step = loaded.step
	if type(_step) == "string" then
		save.step = loaded.step
	end
	if loaded.done == true then
		save.done = true
	end
	local _runId = loaded.runId
	if type(_runId) == "string" then
		save.runId = loaded.runId
	end
	local _elapsed = loaded.elapsed
	if type(_elapsed) == "number" then
		save.elapsed = math.max(0, loaded.elapsed)
	end
	-- Un id inconnu (step renommé/retiré) fait repartir au début plutôt que de bloquer.
	if not save.done and stepIndexById(save.step) == nil then
		save.step = firstStepId()
	end
	return save
end
local function savePlayer(player)
	local _player = player
	if not (loadedPlayers[_player] ~= nil) then
		return nil
	end
	local _player_1 = player
	local state = states[_player_1]
	if not state then
		return nil
	end
	local data = {
		step = state.step,
		done = state.done,
		runId = state.runId,
		elapsed = state.elapsed,
	}
	local success, err = pcall(function()
		return dataStore:SetAsync(keyFor(player), data)
	end)
	if not success then
		warn(`TutorialService: failed to save {player.Name}: {err}`)
	end
end
-- Publie l'étape courante vers le client (attribut répliqué). "" = plus de tutorial.
local function publish(player, stepId)
	player:SetAttribute(STEP_ATTR, stepId)
end
-- Referme le step courant : cumule son temps et renvoie sa durée en secondes.
local function closeStep(state)
	local spent = math.max(0, os.time() - state.stepEnteredAt)
	state.elapsed += spent
	state.stepEnteredAt = os.time()
	return spent
end
local function enterStep(player, state, stepId)
	state.step = stepId
	state.stepEnteredAt = os.time()
	publish(player, stepId)
end
local function finishTutorial(player, state)
	closeStep(state)
	state.done = true
	state.step = ""
	publish(player, "")
	savePlayer(player)
end
-- Avance d'exactement un step (ou termine si c'était le dernier).
local function advanceOne(player, state)
	local index = stepIndexById(state.step)
	if index == nil then
		finishTutorial(player, state)
		return nil
	end
	closeStep(state)
	local nextIndex = index + 1
	if nextIndex >= #TUTORIAL_STEPS then
		finishTutorial(player, state)
		return nil
	end
	enterStep(player, state, TUTORIAL_STEPS[nextIndex + 1].id)
	savePlayer(player)
end
local function setupPlayer(player)
	local save = loadSave(player)
	if save ~= nil then
		local _player = player
		loadedPlayers[_player] = true
	end
	local resolved = save or freshSave()
	-- forceTutorial ignore la sauvegarde : on repart du premier step.
	if forceTutorial then
		resolved.done = false
		resolved.step = firstStepId()
		resolved.elapsed = 0
		resolved.runId = newRunId()
	end
	if resolved.done then
		local _exp = player
		local _object = table.clone(resolved)
		setmetatable(_object, nil)
		_object.step = ""
		_object.stepEnteredAt = os.time()
		states[_exp] = _object
		publish(player, "")
		return nil
	end
	local _object = table.clone(resolved)
	setmetatable(_object, nil)
	_object.stepEnteredAt = os.time()
	local state = _object
	local _player = player
	states[_player] = state
	publish(player, state.step)
end
local TutorialService
TutorialService = {
	init = function(self)
		Players.PlayerAdded:Connect(function(player)
			return task.spawn(function()
				return setupPlayer(player)
			end)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				return setupPlayer(player)
			end)
		end
		Events.TutorialAdvanceEvent.OnServerEvent:Connect(function(player, stepId)
			local _stepId = stepId
			if not (type(_stepId) == "string") then
				return nil
			end
			local _player = player
			local state = states[_player]
			if not state or state.done then
				return nil
			end
			if stepId == SKIP_ID then
				TutorialService:finish(player, true)
				return nil
			end
			TutorialService:advance(player, stepId)
		end)
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			local state = states[_player]
			if state and not state.done then
				closeStep(state)
			end
			savePlayer(player)
			local _player_1 = player
			states[_player_1] = nil
			local _player_2 = player
			loadedPlayers[_player_2] = nil
		end)
		game:BindToClose(function()
			local players = Players:GetPlayers()
			if #players == 0 then
				return nil
			end
			local remaining = #players
			for _, player in players do
				task.spawn(function()
					savePlayer(player)
					remaining -= 1
				end)
			end
			while remaining > 0 do
				task.wait(0.1)
			end
		end)
	end,
	isActive = function(self, player)
		local _player = player
		local state = states[_player]
		return state ~= nil and not state.done
	end,
	getCurrentStep = function(self, player)
		local _player = player
		local state = states[_player]
		if not state or state.done then
			return nil
		end
		return stepById(state.step)
	end,
	advance = function(self, player, stepId)
		local _player = player
		local state = states[_player]
		if not state or state.done or state.step ~= stepId then
			return nil
		end
		advanceOne(player, state)
	end,
	advanceTo = function(self, player, stepId)
		local _player = player
		local state = states[_player]
		if not state or state.done then
			return nil
		end
		local target = stepIndexById(stepId)
		if target == nil then
			return nil
		end
		local guard = 0
		while not state.done and stepIndexById(state.step) ~= nil do
			local current = stepIndexById(state.step)
			if current >= target then
				break
			end
			advanceOne(player, state)
			guard += 1
			if guard > #TUTORIAL_STEPS then
				break
			end
		end
	end,
	finish = function(self, player, _skipped)
		local _player = player
		local state = states[_player]
		if not state or state.done then
			return nil
		end
		finishTutorial(player, state)
	end,
	devRestart = function(self, player)
		local _object = table.clone(freshSave())
		setmetatable(_object, nil)
		_object.stepEnteredAt = os.time()
		local state = _object
		local _player = player
		states[_player] = state
		local _player_1 = player
		loadedPlayers[_player_1] = true
		publish(player, state.step)
		savePlayer(player)
	end,
	devGoto = function(self, player, stepId)
		if stepIndexById(stepId) == nil then
			warn(`TutorialService.devGoto: step inconnu "{stepId}"`)
			return nil
		end
		local _player = player
		local _condition = states[_player]
		if _condition == nil then
			local _object = table.clone(freshSave())
			setmetatable(_object, nil)
			_object.stepEnteredAt = os.time()
			_condition = _object
		end
		local state = _condition
		state.done = false
		local _player_1 = player
		states[_player_1] = state
		local _player_2 = player
		loadedPlayers[_player_2] = true
		enterStep(player, state, stepId)
		savePlayer(player)
	end,
}
return {
	TutorialService = TutorialService,
}
