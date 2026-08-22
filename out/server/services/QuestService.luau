-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local DataStoreService = _services.DataStoreService
local Players = _services.Players
local Workspace = _services.Workspace
local _CheatConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig")
local RESET_DATA_CHEAT = _CheatConfig.resetData
local questCheatKey = _CheatConfig.questCheatKey
local questCheatTokens = _CheatConfig.questCheatTokens
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local _QuestConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "QuestConfig")
local QUESTS = _QuestConfig.QUESTS
local QUEST_RESET_SECONDS = _QuestConfig.QUEST_RESET_SECONDS
local questProgressAttr = _QuestConfig.questProgressAttr
local questResetAttr = _QuestConfig.questResetAttr
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
-- Autorité des quêtes (§6.26). Tient la progression de chaque joueur, verse les
-- ScrollToken à l'accomplissement et publie tout via des ATTRIBUTS joueur — donc
-- répliqués vers le client sans le moindre RemoteEvent :
--   Q_<id>  progression courante
--   QR_<id> instant de reset en temps SERVEUR (0 = quête disponible)
--
-- Le client ne fait jamais que lire ces attributs. Les seuls points d'entrée de
-- progression sont les appels à `report` posés dans le code de jeu :
-- ButtonInGameModule (décollage + claim) et ShopService (achat validé).
--
-- Persistance : store dédié (même patron que PlayerProgressionService), avec le
-- cooldown stocké en os.time() ABSOLU pour qu'il continue de s'écouler hors ligne.
-- L'attribut, lui, est exprimé en Workspace:GetServerTimeNow() : c'est la seule
-- horloge que client et serveur partagent réellement.
local STORE_NAME = "QuestData_v1"
local dataStore = DataStoreService:GetDataStore(STORE_NAME)
-- Cadence du balayage des cooldowns arrivés à terme. 1s : le libellé côté client
-- descend à la seconde, inutile d'être plus fin.
local COOLDOWN_TICK = 1
-- Forme persistée (tables plates, indexées par questId).
local states = {}
-- Seuls les joueurs dont le chargement a RÉUSSI sont sauvegardables — un échec
-- transitoire du DataStore ne doit jamais écraser une progression existante.
local loadedPlayers = {}
local function keyFor(player)
	return `Player_{player.UserId}`
end
local function emptyState()
	return {
		progress = {},
		resetAt = {},
	}
end
-- Écrit le couple d'attributs d'une quête. `resetAt` est converti d'os.time()
-- (persistant) vers le temps serveur (partagé avec le client) au moment de la
-- publication : les deux horloges avancent à la même vitesse, seul l'offset diffère.
local function publish(player, state, quest)
	local _player = player
	local _exp = questProgressAttr(quest.id)
	local _progress = state.progress
	local _id = quest.id
	local _condition = _progress[_id]
	if _condition == nil then
		_condition = 0
	end
	_player:SetAttribute(_exp, _condition)
	local _resetAt = state.resetAt
	local _id_1 = quest.id
	local deadline = _resetAt[_id_1]
	if deadline == nil then
		player:SetAttribute(questResetAttr(quest.id), 0)
		return nil
	end
	local remaining = math.max(0, deadline - os.time())
	player:SetAttribute(questResetAttr(quest.id), Workspace:GetServerTimeNow() + remaining)
end
local function publishAll(player, state)
	for _, quest in QUESTS do
		publish(player, state, quest)
	end
end
local function loadState(player)
	if RESET_DATA_CHEAT then
		warn(`QuestService: resetData cheat — wiping in-memory state for {player.Name}`)
		return emptyState()
	end
	local success, result = pcall(function()
		return dataStore:GetAsync(keyFor(player))
	end)
	if not success then
		warn(`QuestService: failed to load {player.Name}: {result}`)
		return nil
	end
	local state = emptyState()
	if result == nil or not (type(result) == "table") then
		return state
	end
	local stored = result
	for _, quest in QUESTS do
		local _deadline = stored.resetAt
		if _deadline ~= nil then
			_deadline = _deadline[quest.id]
		end
		local deadline = _deadline
		-- Un cooldown expiré pendant la déconnexion est simplement oublié — et avec
		-- lui la progression, exactement comme un reset survenu en ligne.
		if type(deadline) == "number" and deadline > os.time() then
			local _resetAt = state.resetAt
			local _id = quest.id
			_resetAt[_id] = deadline
			local _progress = state.progress
			local _id_1 = quest.id
			local _target = quest.target
			_progress[_id_1] = _target
			continue
		end
		if type(deadline) == "number" then
			continue
		end
		local _progress = stored.progress
		if _progress ~= nil then
			_progress = _progress[quest.id]
		end
		local progress = _progress
		if type(progress) == "number" then
			local _progress_1 = state.progress
			local _id = quest.id
			local _arg1 = math.max(0, progress)
			_progress_1[_id] = _arg1
		end
	end
	return state
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
		progress = {},
		resetAt = {},
	}
	for questId, value in state.progress do
		data.progress[questId] = value
	end
	for questId, value in state.resetAt do
		data.resetAt[questId] = value
	end
	local success, err = pcall(function()
		return dataStore:SetAsync(keyFor(player), data)
	end)
	if not success then
		warn(`QuestService: failed to save {player.Name}: {err}`)
	end
end
local function setupPlayer(player)
	local loaded = loadState(player)
	local state = loaded or emptyState()
	local _player = player
	states[_player] = state
	if loaded ~= nil then
		local _player_1 = player
		loadedPlayers[_player_1] = true
	end
	publishAll(player, state)
end
-- Quête accomplie : la progression est figée à l'objectif (la barre reste pleine
-- pendant le cooldown), la récompense est versée, le cooldown démarre.
local function complete(player, state, quest)
	local _progress = state.progress
	local _id = quest.id
	local _target = quest.target
	_progress[_id] = _target
	local _resetAt = state.resetAt
	local _id_1 = quest.id
	local _arg1 = os.time() + QUEST_RESET_SECONDS
	_resetAt[_id_1] = _arg1
	publish(player, state, quest)
	PlayerDataService:add(player, "ScrollTokens", quest.reward)
	-- Présentation : le client s'occupe du bandeau Epic + de la pluie d'icônes.
	Events.QuestCompletedEvent:FireClient(player)
	AnalyticsService:custom(player, "QuestCompleted", quest.reward, quest.id)
end
-- Fin de cooldown : la quête repart de zéro et redevient "Enable".
local function rearm(player, state, quest)
	local _resetAt = state.resetAt
	local _id = quest.id
	_resetAt[_id] = nil
	local _progress = state.progress
	local _id_1 = quest.id
	_progress[_id_1] = nil
	publish(player, state, quest)
end
local function tickCooldowns()
	local now = os.time()
	for player, state in states do
		if next(state.resetAt) == nil then
			continue
		end
		for _, quest in QUESTS do
			local _resetAt = state.resetAt
			local _id = quest.id
			local deadline = _resetAt[_id]
			if deadline ~= nil and deadline <= now then
				rearm(player, state, quest)
			end
		end
	end
end
local QuestService = {
	init = function(self)
		Players.PlayerAdded:Connect(setupPlayer)
		for _, player in Players:GetPlayers() do
			setupPlayer(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			savePlayer(player)
			local _player = player
			loadedPlayers[_player] = nil
			local _player_1 = player
			states[_player_1] = nil
		end)
		-- Roblox waits up to 30s on BindToClose — save everyone in parallel so a
		-- slow save doesn't starve the others before the deadline.
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
		task.spawn(function()
			while true do
				task.wait(COOLDOWN_TICK)
				tickCooldowns()
			end
		end)
		-- Cheat de dev (touche U) : termine la première quête disponible par le chemin
		-- NORMAL — récompense, bandeau Epic et pluie d'icônes compris — puis crédite le
		-- bonus de test. L'event n'est même pas branché quand le cheat est éteint, il
		-- est donc totalement inerte en production.
		if questCheatKey then
			Events.QuestCheatEvent.OnServerEvent:Connect(function(player)
				local _player = player
				local state = states[_player]
				if not state then
					return nil
				end
				-- ▼ ReadonlyArray.find ▼
				local _callback = function(quest)
					local _resetAt = state.resetAt
					local _id = quest.id
					return _resetAt[_id] == nil
				end
				local _result
				for _i, _v in QUESTS do
					if _callback(_v, _i - 1, QUESTS) == true then
						_result = _v
						break
					end
				end
				-- ▲ ReadonlyArray.find ▲
				local available = _result
				-- Tout en cooldown : on garde au moins la célébration.
				if available then
					complete(player, state, available)
				else
					Events.QuestCompletedEvent:FireClient(player)
				end
				PlayerDataService:add(player, "ScrollTokens", questCheatTokens)
			end)
		end
	end,
	report = function(self, player, metric, amount)
		if amount <= 0 then
			return nil
		end
		local _player = player
		local state = states[_player]
		if not state then
			return nil
		end
		for _, quest in QUESTS do
			if quest.metric ~= metric then
				continue
			end
			local _resetAt = state.resetAt
			local _id = quest.id
			if _resetAt[_id] ~= nil then
				continue
			end
			local _progress = state.progress
			local _id_1 = quest.id
			local _condition = _progress[_id_1]
			if _condition == nil then
				_condition = 0
			end
			local nextProgress = _condition + amount
			if nextProgress >= quest.target then
				complete(player, state, quest)
			else
				local _progress_1 = state.progress
				local _id_2 = quest.id
				_progress_1[_id_2] = nextProgress
				publish(player, state, quest)
			end
		end
	end,
}
return {
	QuestService = QuestService,
}
