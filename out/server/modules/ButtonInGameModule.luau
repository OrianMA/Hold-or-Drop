-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local Workspace = _services.Workspace
local _CheatConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig")
local boostCriticalClaim = _CheatConfig.boostCriticalClaim
local boostedCriticalClaimChance = _CheatConfig.boostedCriticalClaimChance
local invincible = _CheatConfig.invincible
local logExplosionForecast = _CheatConfig.logExplosionForecast
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
local RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher").RocketLauncher
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
local TutorialHooks = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialHooks").TutorialHooks
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local MULTIPLIER_TICK_RATE = _RocketGameConfig.MULTIPLIER_TICK_RATE
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local MULTIPLIER_PER_STUD = _RocketGameConfig.MULTIPLIER_PER_STUD
local EXPLOSION_VIEW_DELAY = _RocketGameConfig.EXPLOSION_VIEW_DELAY
local PERFECT_CLAIM_MULTIPLIER = _RocketGameConfig.PERFECT_CLAIM_MULTIPLIER
local CRITICAL_CLAIM_CHANCE = _RocketGameConfig.CRITICAL_CLAIM_CHANCE
local CRITICAL_CLAIM_MULTIPLIER = _RocketGameConfig.CRITICAL_CLAIM_MULTIPLIER
local perfectClaimWindow = _RocketGameConfig.perfectClaimWindow
local multiplierAfter = _RocketGameConfig.multiplierAfter
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local resistanceRiskParams = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ResistanceCurve").resistanceRiskParams
local _MegaRocketConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MegaRocketConfig")
local MEGA_ROCKET_BASE_CASH_MULT = _MegaRocketConfig.MEGA_ROCKET_BASE_CASH_MULT
local hasMegaRocket = _MegaRocketConfig.hasMegaRocket
local MegaRocketService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "MegaRocketService").MegaRocketService
-- ── Game tuning ───────────────────────────────────────────────────────────────
local TICK_RATE = 0.5
-- Lot de consolation sur une perte (explosion sans claim) : baseCash / 3 —
-- FORFAITAIRE, sans le multiplicateur. Pas de popup de fin.
local LOSS_CONSOLATION_DIVISOR = 3
-- "Go Home" (retour à la base après un claim) : délai avant de reposer le rig sur le pad,
-- le temps que la caméra soit revenue au joueur.
local GO_HOME_RESET_DELAY = 0.6
-- ── Durée de vol : cloche de Gauss (log-normale) ─────────────────────────────
-- La durée d'un vol est TIRÉE D'UN COUP au décollage dans une cloche de Gauss — pas
-- accumulée dé après dé. Le tirage est gaussien sur une échelle MULTIPLICATIVE du
-- temps ("4 s ×÷ 1.4") et non additive ("4 s ± 1.2 s") : la cloche a la même forme,
-- même pic net et mêmes chances qui s'effondrent quand on s'éloigne, mais elle ne
-- peut jamais produire une durée nulle ou négative — et son côté long reste libre de
-- s'allonger, ce qui laisse exister le coup rare. Une cloche additive serait fermée
-- des deux côtés : pour garder le bas au-dessus de zéro il faudrait serrer le haut,
-- et le vol jackpot n'existerait plus.
--   • FLIGHT_TIME_MEAN  — durée MOYENNE d'un vol à Resistance 0.
--   • FLIGHT_TIME_SIGMA — largeur de la cloche. Seul bouton pour rendre le jeu plus
--     ou moins imprévisible ; il ne déplace pas la moyenne (la médiane est recalculée
--     pour compenser).
-- Repères à Resistance 0 (μ = 7 s, σ = 0.35) : 68 % des vols entre 4.7 et 9.3 s,
-- 95 % entre 3.3 et 13.0 s, plafond observé ~33 s. Côté gain : multiplicateur moyen
-- ×1.50, un ×3 tous les ~185 runs.
local FLIGHT_TIME_MEAN = 7
local FLIGHT_TIME_SIGMA = 0.35
-- Garde-fous du tirage : la cloche n'est pas bornée, on coupe les deux queues bien
-- au-delà de ce qu'un joueur verra jamais.
local FLIGHT_TIME_MIN = 0.1
local FLIGHT_TIME_MAX = 60
-- Médiane telle que la MOYENNE vaille FLIGHT_TIME_MEAN — sur une échelle
-- multiplicative, moyenne = médiane × e^(σ²/2). Régler σ ne déplace donc pas la moyenne.
local FLIGHT_TIME_MEDIAN = FLIGHT_TIME_MEAN * math.exp(-(FLIGHT_TIME_SIGMA * FLIGHT_TIME_SIGMA) / 2)
local EXPLOSION_SOUND_ID = AudioConfig.sfx.explosion.id
local EXPLOSION_SOUND_VOLUME = AudioConfig.sfx.explosion.volume
local EXPLOSION_SOUND_ROLLOFF = 120
-- ── Sound preloading ──────────────────────────────────────────────────────────
-- A template Sound in ReplicatedStorage replicates to all clients on join,
-- causing them to pre-buffer the audio asset before any explosion fires.
-- Cloning a pre-buffered template eliminates the CDN fetch delay at runtime.
local assetsFolder = (function()
	local existing = ReplicatedStorage:FindFirstChild("HoldOrDropAssets")
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "HoldOrDropAssets"
	folder.Parent = ReplicatedStorage
	return folder
end)()
local explosionSoundTemplate = (function()
	local sound = Instance.new("Sound")
	sound.Name = "ExplosionSound"
	sound.SoundId = EXPLOSION_SOUND_ID
	sound.Volume = EXPLOSION_SOUND_VOLUME
	sound.RollOffMaxDistance = EXPLOSION_SOUND_ROLLOFF
	sound.Parent = assetsFolder
	return sound
end)()
-- ── Helpers ───────────────────────────────────────────────────────────────────
-- ── Explosion-time preload ──────────────────────────────────────────────────────
-- Tire, une fois au décollage, l'instant EXACT où la fusée explosera. Le run déclenche
-- ensuite l'explosion pile à l'heure, au lieu de relancer un dé à chaque tick et de la
-- découvrir en retard. Résultat continu — aucun alignement sur un pas de temps.
--
-- Le profil de Resistance déforme la cloche sans en changer les proportions :
--   • safeWindow — secondes garanties, AJOUTÉES au tirage. La promesse du shop
--     ("Vol garanti X s") est donc tenue littéralement, quoi que sorte le dé.
--   • riskScale  — multiplie la médiane par riskScale^(-1/3), l'étirement documenté
--     dans ResistanceCurve. Sur une échelle multiplicative, étirer la médiane étire
--     la cloche entière : elle garde exactement sa forme à tous les niveaux.
local function rollExplosionTime(params)
	-- Box–Muller : une normale centrée réduite à partir de deux uniformes.
	-- 1 - math.random() ∈ (0,1] ⇒ jamais log(0).
	local gauss = math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random())
	local median = FLIGHT_TIME_MEDIAN * params.riskScale ^ (-1 / 3)
	local flight = params.safeWindow + median * math.exp(FLIGHT_TIME_SIGMA * gauss)
	return math.clamp(flight, FLIGHT_TIME_MIN, FLIGHT_TIME_MAX)
end
-- Plays the 3D explosion boom at `pos` (heard by everyone). Cloned from the
-- pre-buffered template — no CDN fetch on the client. Parented to Terrain via an
-- Attachment for proper 3D rolloff.
local function playExplosionSoundAt(pos)
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = pos
	local sound = explosionSoundTemplate:Clone()
	sound.Parent = attachment
	sound:Play()
	sound.Ended:Connect(function()
		return attachment:Destroy()
	end)
end
-- Cheat `logExplosionForecast` : imprime l'issue précalculée du vol. Le multiplicateur
-- prévu est reconstruit par `multiplierAfter`, qui rejoue exactement la boucle
-- multiplicateur (même tick, même vitesse) — c'est donc la valeur que le joueur verra à
-- l'instant de l'explosion s'il ne claim pas avant.
local function logForecast(player, deadline, effectiveSpeed, baseCash)
	if deadline == math.huge then
		print(`[CHEAT] {player.Name} — la fusée n'explosera pas (invincible / run scripté sans risque)`)
		return nil
	end
	local predicted = multiplierAfter(effectiveSpeed, deadline)
	print(string.format("[CHEAT] %s — explosion dans %.2fs | multiplicateur prévu ×%.2f (~$%d) | Perfect Claim si claim après %.2fs", player.Name, deadline, predicted, math.floor(baseCash * predicted), deadline - perfectClaimWindow(deadline)))
end
-- ── Public API ────────────────────────────────────────────────────────────────
-- Used by the ButtonMenu Quit flow — release/explosion endings transition
-- through EndGameButtonModule.enter() instead, which performs the same cleanup.
-- Native left/right movement redirected to the flying rocket. The client sends the
-- quantised steering intent (-1/0/+1) only when it changes; we resolve the player's
-- active room and forward it. setSteer is a no-op when the room isn't flying, so input
-- outside a run is harmless — no per-game connection to manage. Registered once on load.
Events.RocketSteerEvent.OnServerEvent:Connect(function(player, dir)
	local session = ButtonSessionService:getSession(player)
	if not session then
		return nil
	end
	local _exp = session.room
	local _dir = dir
	RocketLauncher:setSteer(_exp, if type(_dir) == "number" then dir else 0)
end)
local function endButtonGame(player)
	ButtonSessionService:cleanup(player)
	UiService:HideCurrent(player)
end
local function startButtonGame(player, session)
	local room = session.room
	-- EffectiveBaseCash already folds in every money multiplier (rebirth multiplies;
	-- money game-pass tier + community add inside that boost factor — see
	-- shared/ShopConfig.moneyMult). Read once — held for the session so a mid-run
	-- boost change can't alter an in-progress hold.
	-- Mega Rocket (§6.24) : si le joueur a une Mega Rocket sur le pad, CE vol paie
	-- ×MEGA_ROCKET_BASE_CASH_MULT sur le base cash. Lu une fois, comme le reste — et
	-- consommé seulement en FIN de vol (respawnRocket), pour que le client garde la
	-- même base sur son aperçu de gain pendant toute la partie.
	local megaRun = hasMegaRocket(player)
	local baseCash = PlayerProgressionService:get(player, "EffectiveBaseCash") * (if megaRun then MEGA_ROCKET_BASE_CASH_MULT else 1)
	-- Resistance (0..100, incl. the pass) reshapes the explosion risk — see
	-- resistanceRiskParams. Read once and resolved to its risk profile for the run.
	local resistance = PlayerProgressionService:get(player, "Resistance")
	local riskParams = resistanceRiskParams(resistance)
	-- Rocket Speed stat value (≥1) scales the rocket's ascent. Read once for the run.
	local rocketSpeed = PlayerProgressionService:get(player, "RocketSpeed")
	-- Démarre à 1.00x puis grimpe au rythme de la vitesse RÉELLE de la fusée : tant
	-- qu'elle est lente (Rocket Speed bas), le multiplicateur bouge à peine ; plus la
	-- fusée va vite, plus il grimpe (voir RocketGameConfig).
	local currentMultiplier = STARTING_MULTIPLIER
	local isActive = true
	-- Analytics: one funnel session id for this run (CoreRun: Launch → Claim → Banked).
	local runId = AnalyticsService:newRunId()
	-- Preload the "chance" at launch: tire l'instant exact où la fusée explosera dans une
	-- courbe de Gauss (voir rollExplosionTime). The run then fires the explosion at this
	-- scheduled moment — no per-tick RNG, no discovery delay.
	-- Tutorial : si le step courant impose un scénario (gel, explosion programmée), le
	-- director le joue et fournit la deadline d'explosion — qu'il peut réécrire au claim.
	-- undefined hors tutorial → comportement normal intégral.
	local scripted = TutorialHooks:beginRun(player, room)
	-- invincible ⇒ never explodes.
	local explosionAt = if invincible then math.huge else rollExplosionTime(riskParams)
	Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
	-- La fusée décolle dès le début du gameplay, à une vitesse pilotée par le stat
	-- Rocket Speed du joueur (1 = rampe). Sa vélocité pilote ensuite le multiplicateur.
	-- Un run scripté peut la ralentir (tutorial) ; hors tutorial le facteur vaut 1.
	-- `launchClock` = horloge de référence du vol : `os.clock() - launchClock` donne le
	-- temps de vol réel (précis à la frame), à comparer à la deadline d'explosion pour
	-- mesurer le Perfect Claim. La boucle risque, elle, n'avance que par pas de TICK_RATE.
	local launchClock = os.clock()
	local _result = scripted
	if _result ~= nil then
		_result = _result.speedFactor
	end
	local _condition = _result
	if _condition == nil then
		_condition = 1
	end
	local effectiveSpeed = rocketSpeed * _condition
	RocketLauncher:launch(room, effectiveSpeed)
	-- Fin de vol : le rig revient sur le pad et une fusée NEUVE y est posée. Si ce vol
	-- portait la Mega Rocket, elle est consommée AVANT le replacement — la fusée qui
	-- apparaît est donc une fusée normale. Un vol lancé AVANT le top de l'événement ne
	-- consomme rien : le joueur retrouve sa Mega Rocket sur le pad.
	local respawnRocket = function()
		if megaRun then
			MegaRocketService:consume(player)
		end
		RocketLauncher:reset(room)
		RocketPlacer:place(room)
	end
	-- Cheat de dev : annonce l'issue déjà tirée du vol (voir CheatConfig). C'est l'état AU
	-- DÉCOLLAGE — en tutorial, un run scripté peut réécrire sa deadline au claim.
	if logExplosionForecast then
		local _exp = player
		local _result_1 = scripted
		if _result_1 ~= nil then
			_result_1 = _result_1.explosionAt()
		end
		local _condition_1 = _result_1
		if _condition_1 == nil then
			_condition_1 = explosionAt
		end
		logForecast(_exp, _condition_1, effectiveSpeed, baseCash)
	end
	-- Analytics: run started (custom counter + funnel step 1 + onboarding step 2).
	AnalyticsService:custom(player, "RocketLaunched", rocketSpeed)
	AnalyticsService:runStep(player, runId, 1, "Launch")
	AnalyticsService:onboardingStep(player, 2, "Launch")
	-- Claim : le joueur VERROUILLE le multiplicateur courant en gain garanti. La fusée ne
	-- s'arrête PAS — elle continue de monter (le multiplicateur affiché grimpe encore,
	-- purement visuel) jusqu'à l'explosion, où le payout se fait au multiplicateur
	-- verrouillé EXACT (voir la boucle risque plus bas). Remplace l'ancien "release".
	local claimed = false
	local claimedMultiplier = STARTING_MULTIPLIER
	-- Les bonus de claim (Perfect ×3 / Critical ×10) ne touchent PAS le multiplicateur :
	-- ils multiplient le BASE CASH verrouillé. Le payout final est rigoureusement le même
	-- (base × mult), mais le joueur voit clairement quelle valeur a grossi.
	local claimBonus = 1
	local claimedBaseCash = baseCash
	local claimConn = Events.ClaimButtonEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive or claimed then
			return nil
		end
		claimed = true
		-- Perfect Claim : le claim tombe dans la toute dernière fenêtre avant l'explosion
		-- PRÉVUE → base cash ×3. La deadline est lue AVANT scripted.onClaim(), qui la réécrit
		-- en tutorial (sinon un run scripté offrirait un perfect gratuit).
		local deadline = if scripted ~= nil then scripted.explosionAt() else explosionAt
		local remaining = deadline - (os.clock() - launchClock)
		local perfect = remaining <= perfectClaimWindow(deadline)
		-- Critical Claim : coup de dé pur à chaque claim (5 %) → ×10 sur le base cash.
		-- Indépendant du Perfect Claim : les deux peuvent tomber ensemble et se multiplient.
		-- Cheat de dev : `boostCriticalClaim` monte la chance à 50 % (voir CheatConfig).
		local criticalChance = if boostCriticalClaim then boostedCriticalClaimChance else CRITICAL_CLAIM_CHANCE
		local critical = math.random() < criticalChance
		-- Multiplicateur verrouillé = valeur exacte au moment du claim, SANS bonus : le
		-- multiplicateur est ce que le joueur a gagné en tenant, rien d'autre ne le gonfle.
		claimedMultiplier = currentMultiplier
		-- Les bonus s'appliquent au base cash. Toutes les branches de payout (explosion
		-- post-claim, Go Home) et la popup de fin lisent `claimedBaseCash × claimedMultiplier`
		-- — le gain final est donc identique à l'ancien calcul.
		claimBonus = (if perfect then PERFECT_CLAIM_MULTIPLIER else 1) * (if critical then CRITICAL_CLAIM_MULTIPLIER else 1)
		claimedBaseCash = baseCash * claimBonus
		Events.ClaimAcceptedEvent:FireClient(player, claimedMultiplier, perfect, critical, claimedBaseCash)
		local _result_1 = scripted
		if _result_1 ~= nil then
			_result_1.onClaim()
		end
		-- Analytics: claim locked (custom counter + funnel step 2 + onboarding step 3).
		AnalyticsService:custom(player, "RunClaimed", claimedMultiplier)
		if perfect then
			AnalyticsService:custom(player, "PerfectClaim", claimedMultiplier)
		end
		if critical then
			AnalyticsService:custom(player, "CriticalClaim", claimedMultiplier)
		end
		AnalyticsService:runStep(player, runId, 2, "Claim")
		AnalyticsService:onboardingStep(player, 3, "Claim")
	end)
	-- "Go Home" : après un claim, le joueur peut rentrer à la base sans attendre
	-- l'explosion. La fusée s'arrête net et le gain VERROUILLÉ est payé exactement comme
	-- après une explosion post-claim — simplement sans explosion. Refusé tant qu'on n'a
	-- pas claim (sinon ce serait une sortie gratuite du risque).
	local goHomeConn
	goHomeConn = Events.GoHomeEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive or not claimed then
			return nil
		end
		isActive = false
		claimConn:Disconnect()
		goHomeConn:Disconnect()
		RocketLauncher:stop(room)
		local earned = math.floor(claimedBaseCash * claimedMultiplier)
		-- exploded=false : c'est le client qui ramène la caméra au joueur (retour à la base).
		Events.GameResultEvent:FireClient(player, false, earned, claimedMultiplier)
		-- La popup reçoit le base cash BRUT + le facteur de bonus : elle montre d'abord la
		-- base grimper (×3 / ×10) avant d'y appliquer le multiplicateur.
		EndGameButtonModule:enter(player, "released", baseCash, claimedMultiplier, earned, 1, claimBonus)
		-- Analytics: win banked early (Go Home) — funnel step 3 + custom counter.
		AnalyticsService:runStep(player, runId, 3, "Banked")
		AnalyticsService:custom(player, "RunGoHome", earned)
		-- On laisse la caméra revenir au joueur avant de reposer le rig sur le pad
		-- (sinon la fusée se téléporterait sous les yeux du joueur), puis la fusée est
		-- réinstanciée neuve sur le pad — exactement comme après une explosion.
		task.delay(GO_HOME_RESET_DELAY, function()
			respawnRocket()
		end)
	end)
	-- ── Boucle multiplier ─────────────────────────────────────────────────────
	-- Le multiplicateur suit la vitesse RÉELLE de la fusée : chaque tick on ajoute
	-- `vélocité × tick × MULTIPLIER_PER_STUD` (= la distance que la fusée vient de
	-- monter). La vélocité part de 0 et accélère, donc le multiplicateur est quasi
	-- figé au décollage puis grimpe d'autant plus vite que la fusée va vite (Rocket
	-- Speed élevé). Indépendant de la boucle risque.
	task.spawn(function()
		while isActive do
			task.wait(MULTIPLIER_TICK_RATE)
			if not isActive then
				break
			end
			local climbed = RocketLauncher:getVelocity(room) * MULTIPLIER_TICK_RATE
			currentMultiplier += climbed * MULTIPLIER_PER_STUD
			Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
		end
	end)
	-- ── Boucle risque / explosion planifiée ──────────────────────────────────────
	-- Rafraîchit la barre de risque à TICK_RATE et déclenche l'explosion à l'instant
	-- `explosionAt` précalculé au décollage — plus aucun tirage aléatoire par tick.
	task.spawn(function()
		local timeHeld = 0
		while isActive do
			-- La deadline est relue à CHAQUE tour : le tutorial la réécrit au claim.
			local deadline = if scripted ~= nil then scripted.explosionAt() else explosionAt
			-- Avance jusqu'au prochain pas sans jamais dépasser l'instant d'explosion
			-- précalculé → l'explosion tombe pile à l'heure.
			local nextStep = math.min(timeHeld + TICK_RATE, deadline)
			task.wait(nextStep - timeHeld)
			if not isActive then
				break
			end
			timeHeld = nextStep
			if not invincible and timeHeld >= deadline then
				isActive = false
				claimConn:Disconnect()
				goHomeConn:Disconnect()
				if claimed then
					-- Le joueur a claim avant l'explosion → gain GARANTI au multiplicateur
					-- verrouillé. La fusée explose (spectacle), puis le payout se fait au
					-- claimedMultiplier EXACT, sans aucune pénalité.
					local rocketPos = room.movableModel:GetPivot().Position
					RocketLauncher:explode(room)
					playExplosionSoundAt(rocketPos)
					-- Le client garde la caméra orbitale sur la fusée qui explose, puis revient.
					Events.PlayerKilledEvent:FireClient(player)
					task.wait(EXPLOSION_VIEW_DELAY)
					respawnRocket()
					local earned = math.floor(claimedBaseCash * claimedMultiplier)
					-- exploded=true : côté client PlayerKilledEvent gère la caméra (pas de double retour).
					Events.GameResultEvent:FireClient(player, true, earned, claimedMultiplier)
					EndGameButtonModule:enter(player, "killed", baseCash, claimedMultiplier, earned, 1, claimBonus)
					-- Analytics: guaranteed win landed after the explosion — funnel step 3.
					AnalyticsService:runStep(player, runId, 3, "Banked")
					return nil
				end
				-- Pas de claim à temps : perte sèche. La FUSÉE explose, pas le joueur —
				-- pas de fling, pas de mort. explode() stoppe lui-même l'ascension après
				-- avoir capturé sa vitesse, pour que les débris conservent l'élan vers le
				-- haut (la fusée continue de monter en explosant) avant que la gravité ne
				-- les rattrape.
				Events.ButtonExplodedEvent:FireClient(player)
				-- Deregister button immediately (avoids WaitForChild blocking the UI)
				ButtonSessionService:cleanup(player)
				do
					local rocketPos = room.movableModel:GetPivot().Position
					RocketLauncher:explode(room)
					playExplosionSoundAt(rocketPos)
					-- Le client garde la caméra orbitale sur la fusée qui explose, puis revient.
					Events.PlayerKilledEvent:FireClient(player)
					-- On laisse l'explosion se jouer avant de ramener le rig.
					task.wait(EXPLOSION_VIEW_DELAY)
					respawnRocket()
					-- Perte : PAS de popup de fin. Lot de consolation forfaitaire
					-- (baseCash / 3, sans le multiplicateur) montré par un seul texte qui
					-- saute puis file vers l'argent du HUD (client LossRewardBehavior).
					local reward = math.floor(baseCash / LOSS_CONSOLATION_DIVISOR)
					Events.GameResultEvent:FireClient(player, true, reward, currentMultiplier)
					EndGameButtonModule:enterRewardOnly(player, reward)
					-- Analytics: run lost (never claimed) — custom counter with the multiplier
					-- the player greeded to. No funnel step 3 → the drop-off is the loss rate.
					AnalyticsService:custom(player, "RunLost", currentMultiplier)
				end
				return nil
			end
		end
	end)
end
return {
	endButtonGame = endButtonGame,
	startButtonGame = startButtonGame,
}
