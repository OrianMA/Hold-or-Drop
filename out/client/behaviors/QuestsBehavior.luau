-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local _QuestConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "QuestConfig")
local QUESTS = _QuestConfig.QUESTS
local QUEST_AVAILABLE_LABEL = _QuestConfig.QUEST_AVAILABLE_LABEL
local SCROLL_TOKENS_ATTR = _QuestConfig.SCROLL_TOKENS_ATTR
local formatQuestTimer = _QuestConfig.formatQuestTimer
local questProgressAttr = _QuestConfig.questProgressAttr
local questResetAttr = _QuestConfig.questResetAttr
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
-- Ouvre / ferme le panneau des quêtes (InGameUI/QuestsPanel) et le peint.
--   • HUD/ButtonsFrame/QuestsFrame/ImageButton ouvre
--   • Header/CloseButtonFrame/CloseButton ferme
-- Ouvrir masque le HUD persistant (même patron que ShopBehavior / DailyRewards).
--
-- Tout ce qui s'affiche vient d'attributs répliqués — ScrollTokens pour le compteur
-- du header, Q_<id> / QR_<id> pour chaque ligne (voir server/services/QuestService).
-- Aucun aller-retour réseau : le client ne fait que lire et peindre.
--
-- Une ligne = une Frame de Body/ScrollingFrame, nommée dans shared/QuestConfig :
--   QuestTitletext                        titre de la quête
--   TimeLeftText                          "Enable" ou "Reset in : 4m 32s"
--   ProgressionFrame/CurrentProgressionFrame   barre (taille X en scale, 0..1)
--   ProgressionFrame/TextLabel            "55 / 100"
--   Rewardtext                            "+1.25K"
local player = Players.LocalPlayer
local POPUP_NAME = "QuestsPanel"
-- Plus petite largeur de barre affichable : en dessous, le sliver est illisible
-- (coins arrondis + contour qui s'écrasent), donc on masque la barre. Même
-- raisonnement que la barre de rebirth du HUD.
local MIN_VISIBLE_PROGRESS = 0.013
-- Cadence de rafraîchissement des comptes à rebours, uniquement pendant que le
-- panneau est ouvert (fermé, ce code ne coûte rien).
local TIMER_TICK = 1
local function scrollTokens()
	local _condition = (player:GetAttribute(SCROLL_TOKENS_ATTR))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function questProgress(quest)
	local _condition = (player:GetAttribute(questProgressAttr(quest.id)))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
-- Instant de reset en temps serveur ; 0 = quête disponible.
local function questResetAt(quest)
	local _condition = (player:GetAttribute(questResetAttr(quest.id)))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
-- Résout une ligne. FindFirstChild (et non WaitForChild) partout : une Frame
-- absente ou mal nommée doit coûter UNE ligne de quête, jamais le blocage de tous
-- les init clients qui suivent dans main.client.ts.
local function readRow(scrollingFrame, quest)
	local frame = scrollingFrame:FindFirstChild(quest.frameName)
	if not frame then
		warn(`QuestsBehavior: {quest.frameName} introuvable — quête {quest.id} non affichée`)
		return nil
	end
	local title = frame:FindFirstChild("QuestTitletext")
	local timeLeft = frame:FindFirstChild("TimeLeftText")
	local progressionFrame = frame:FindFirstChild("ProgressionFrame")
	local _fill = progressionFrame
	if _fill ~= nil then
		_fill = _fill:FindFirstChild("CurrentProgressionFrame")
	end
	local fill = _fill
	local _progressText = progressionFrame
	if _progressText ~= nil then
		_progressText = _progressText:FindFirstChild("TextLabel")
	end
	local progressText = _progressText
	local reward = frame:FindFirstChild("Rewardtext")
	local _result = title
	if _result ~= nil then
		_result = _result:IsA("TextLabel")
	end
	local _condition = not _result
	if not _condition then
		local _result_1 = timeLeft
		if _result_1 ~= nil then
			_result_1 = _result_1:IsA("TextLabel")
		end
		_condition = not _result_1
		if not _condition then
			local _result_2 = fill
			if _result_2 ~= nil then
				_result_2 = _result_2:IsA("Frame")
			end
			_condition = not _result_2
			if not _condition then
				local _result_3 = progressText
				if _result_3 ~= nil then
					_result_3 = _result_3:IsA("TextLabel")
				end
				_condition = not _result_3
				if not _condition then
					local _result_4 = reward
					if _result_4 ~= nil then
						_result_4 = _result_4:IsA("TextLabel")
					end
					_condition = not _result_4
				end
			end
		end
	end
	if _condition then
		warn(`QuestsBehavior: {quest.frameName} incomplet — quête {quest.id} non affichée`)
		return nil
	end
	return {
		quest = quest,
		title = title,
		timeLeft = timeLeft,
		fill = fill,
		progressText = progressText,
		reward = reward,
	}
end
-- Le compte à rebours est la seule partie qui bouge sans changement d'attribut :
-- il est réécrit à chaque tick tant que le panneau est ouvert.
local function renderTimer(row)
	local resetAt = questResetAt(row.quest)
	if resetAt <= 0 then
		row.timeLeft.Text = QUEST_AVAILABLE_LABEL
		return nil
	end
	row.timeLeft.Text = formatQuestTimer(resetAt - Workspace:GetServerTimeNow())
end
local function renderRow(row)
	local _binding = row
	local quest = _binding.quest
	local current = math.min(questProgress(quest), quest.target)
	row.title.Text = quest.title
	row.reward.Text = `+{FormatNumber(quest.reward)}`
	row.progressText.Text = `{FormatNumber(math.floor(current))} / {FormatNumber(quest.target)}`
	local progress = math.clamp(current / quest.target, 0, 1)
	if progress < MIN_VISIBLE_PROGRESS then
		row.fill.Visible = false
	else
		row.fill.Visible = true
		row.fill.Size = UDim2.new(progress, 0, 1, 0)
	end
	renderTimer(row)
end
local function init()
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local popup = inGameUI:WaitForChild(POPUP_NAME)
	local header = popup:WaitForChild("Header")
	local closeButton = header:WaitForChild("CloseButtonFrame"):WaitForChild("CloseButton")
	local tokenText = header:WaitForChild("ScrollTokenCount"):WaitForChild("ScrollCountText")
	local scrollingFrame = popup:WaitForChild("Body"):WaitForChild("ScrollingFrame")
	local hud = inGameUI:WaitForChild("HUD")
	local openButton = hud:WaitForChild("ButtonsFrame"):WaitForChild("QuestsFrame"):WaitForChild("ImageButton")
	popup.Visible = false
	local rows = {}
	for _, quest in QUESTS do
		local row = readRow(scrollingFrame, quest)
		if row then
			table.insert(rows, row)
		end
	end
	local renderTokens = function()
		tokenText.Text = FormatNumber(scrollTokens())
	end
	local renderAll = function()
		renderTokens()
		for _, row in rows do
			renderRow(row)
		end
	end
	local timerLoop
	local sinceTick = 0
	local open = function()
		renderAll()
		popup.Visible = true
		InGameUIController:disable()
		local _result = timerLoop
		if _result ~= nil then
			_result:Disconnect()
		end
		sinceTick = TIMER_TICK
		timerLoop = RunService.Heartbeat:Connect(function(delta)
			sinceTick += delta
			if sinceTick < TIMER_TICK then
				return nil
			end
			sinceTick = 0
			for _, row in rows do
				renderTimer(row)
			end
		end)
	end
	local close = function()
		popup.Visible = false
		InGameUIController:enable()
		local _result = timerLoop
		if _result ~= nil then
			_result:Disconnect()
		end
		timerLoop = nil
	end
	openButton.Activated:Connect(open)
	closeButton.Activated:Connect(close)
	-- Le serveur pousse la progression et les cooldowns par attributs : on ne repeint
	-- que la ligne concernée, et seulement si le panneau est à l'écran (fermé, l'état
	-- est de toute façon relu à l'ouverture).
	for _, row in rows do
		for _1, attribute in { questProgressAttr(row.quest.id), questResetAttr(row.quest.id) } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				if popup.Visible then
					renderRow(row)
				end
			end)
		end
	end
	-- Le compteur de tokens, lui, se met à jour même panneau fermé : il est bon marché
	-- et évite tout décalage à l'ouverture suivante.
	player:GetAttributeChangedSignal(SCROLL_TOKENS_ATTR):Connect(renderTokens)
	renderAll()
end
return {
	init = init,
}
