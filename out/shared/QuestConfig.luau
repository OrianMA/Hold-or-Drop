-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
-- ── Quêtes & ScrollToken ──────────────────────────────────────────────────────
-- LE fichier de réglage des quêtes. Trois quêtes (une par métrique) déclinées sur
-- six difficultés : même objectif, seule la valeur change. Chaque quête accomplie
-- paie des ScrollToken (la seconde monnaie, persistée comme l'argent).
--
-- Boucle : la quête est "Enable" tant qu'elle n'est pas remplie → une fois
-- l'objectif atteint la récompense est versée et un cooldown de QUEST_RESET_SECONDS
-- démarre → à la fin du cooldown la progression retombe à 0 et la quête est
-- refaisable. Pendant le cooldown la quête n'enregistre AUCUNE progression.
--
-- Le serveur (server/services/QuestService) est la seule autorité : il tient la
-- progression, verse les tokens et publie l'état via des attributs joueur (donc
-- répliqués, aucun RemoteEvent). Le client (client/behaviors/QuestsBehavior) ne
-- fait que lire ces attributs et peindre le panneau QuestsPanel.
-- Ce que le jeu sait compter. Chaque métrique est alimentée par UN point du code
-- serveur (voir QuestService.report) :
--   RocketsLaunched → ButtonInGameModule, au décollage (une perte compte aussi)
--   UpgradesBought  → ShopService, après un achat validé (niveaux achetés)
--   MultiplierTotal → ButtonInGameModule, au claim (+= multiplicateur verrouillé)
-- Temps avant qu'une quête accomplie ne reparte à zéro (secondes).
local QUEST_RESET_SECONDS = 300
-- Monnaie. Persistée par PlayerDataService (même chemin que Money) et donc
-- répliquée sous ce nom d'attribut.
local SCROLL_TOKENS_ATTR = "ScrollTokens"
-- Libellé du TimeLeftText quand la quête est disponible (pas de cooldown en cours).
local QUEST_AVAILABLE_LABEL = "Enable"
-- Attributs joueur publiés par le serveur, un couple par quête :
--   Q_<id>  → progression courante (nombre)
--   QR_<id> → instant de reset, exprimé en TEMPS SERVEUR (Workspace:GetServerTimeNow),
--             0 = quête disponible. Le temps serveur est synchronisé client/serveur,
--             contrairement à os.time() qui dépend de l'horloge de la machine.
local function questProgressAttr(questId)
	return `Q_{questId}`
end
local function questResetAttr(questId)
	return `QR_{questId}`
end
-- Titre affiché, dérivé de la métrique + de l'objectif — une seule écriture pour
-- les 18 quêtes.
local function titleFor(metric, target)
	local amount = FormatNumber(target)
	if metric == "RocketsLaunched" then
		return `Launch {amount} rockets`
	end
	if metric == "UpgradesBought" then
		return `Buy {amount} upgrades`
	end
	return `Obtain {amount}x multiplier in total`
end
-- ── Réglage ───────────────────────────────────────────────────────────────────
-- Un bloc par difficulté. Les trois tableaux sont dans le MÊME ordre que
-- METRIC_ORDER : décollages (le plus accessible) → améliorations → multiplicateur
-- cumulé (le plus dur), ce qui correspond aux récompenses croissantes.
-- `frames` liste les Frames Studio de la difficulté, dans ce même ordre.
--
-- RAMPE : décollages et améliorations montent d'environ ×3 par difficulté (et non
-- ×5 à ×12 comme au premier jet). Le but est qu'une quête tombe SOUVENT — à ~2.5
-- décollages/min et ~2 achats/min, ça donne grosso modo 2 min / 10 min / 30 min /
-- 1h40 / 5h / 16h par palier, au lieu d'un mur dès la difficulté Mid. Le cooldown
-- de 5 min (QUEST_RESET_SECONDS) fait le reste : les paliers bas se re-terminent en
-- boucle pendant que les hauts avancent en arrière-plan.
--
-- RÉCOMPENSES : calibrées pour ~100K tokens en 20-30 min de jeu, soit le prix de
-- plusieurs améliorations de stat (15-25K) par session. Le calcul tient compte du
-- COOLDOWN, qui est le vrai plafond des petits paliers : une quête ne peut retomber
-- qu'une fois toutes les (temps de complétion + 5 min). Sur 25 min ça donne ~3
-- complétions par quête Easy, ~1 par quête Mid, ~1 quête Hard :
--   Easy 3×(2K+2.5K+3K) = 22.5K · Mid 6K+10K+15K = 31K · Hard ~50K → ~100K.
-- Les trois derniers paliers ne tombent pas dans une session : ce sont des jackpots.
local METRIC_ORDER = { "RocketsLaunched", "UpgradesBought", "MultiplierTotal" }
local TUNING = { {
	difficulty = "Easy",
	frames = { "B1_EasyQuestElement", "B2_EasyQuestElement", "B3_EasyQuestElement" },
	targets = { 5, 3, 10 },
	rewards = { 2_000, 2_500, 3_000 },
}, {
	difficulty = "Mid",
	frames = { "C2_QuestElement", "C3_QuestElement", "C4_QuestElement" },
	targets = { 25, 20, 100 },
	rewards = { 6_000, 10_000, 15_000 },
}, {
	difficulty = "Hard",
	frames = { "D2_QuestElement", "D3_QuestElement", "D4_QuestElement" },
	targets = { 75, 60, 1_000 },
	rewards = { 40_000, 50_000, 60_000 },
}, {
	difficulty = "Insane",
	frames = { "E1_QuestElement", "E2_QuestElement", "E3_QuestElement" },
	targets = { 250, 200, 10_000 },
	rewards = { 200_000, 300_000, 320_000 },
}, {
	difficulty = "Impossible",
	frames = { "F2_QuestElement", "F3_QuestElement", "F4_QuestElement" },
	targets = { 750, 600, 100_000 },
	rewards = { 1_000_000, 1_200_000, 1_400_000 },
}, {
	difficulty = "Unknown",
	frames = { "H2_QuestElement", "H3_QuestElement", "H4_QuestElement" },
	targets = { 2_500, 2_000, 1_000_000 },
	rewards = { 4_000_000, 5_000_000, 5_400_000 },
} }
local function buildQuests()
	local quests = {}
	for _, tuning in TUNING do
		for i = 0, #METRIC_ORDER - 1 do
			local metric = METRIC_ORDER[i + 1]
			local target = tuning.targets[i + 1]
			local _arg0 = {
				id = `{tuning.difficulty}_{metric}`,
				metric = metric,
				difficulty = tuning.difficulty,
				target = target,
				reward = tuning.rewards[i + 1],
				frameName = tuning.frames[i + 1],
				title = titleFor(metric, target),
			}
			table.insert(quests, _arg0)
		end
	end
	return quests
end
local QUESTS = buildQuests()
-- "Reset in : 4m 32s" — le compte à rebours affiché dans TimeLeftText.
local function formatQuestTimer(secondsLeft)
	local total = math.max(0, math.ceil(secondsLeft))
	local minutes = math.floor(total / 60)
	local seconds = total % 60
	return `Reset in : {minutes}m {seconds}s`
end
return {
	questProgressAttr = questProgressAttr,
	questResetAttr = questResetAttr,
	formatQuestTimer = formatQuestTimer,
	QUEST_RESET_SECONDS = QUEST_RESET_SECONDS,
	SCROLL_TOKENS_ATTR = SCROLL_TOKENS_ATTR,
	QUEST_AVAILABLE_LABEL = QUEST_AVAILABLE_LABEL,
	QUESTS = QUESTS,
}
