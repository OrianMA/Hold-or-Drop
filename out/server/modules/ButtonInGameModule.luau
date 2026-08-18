-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local Workspace = _services.Workspace
local invincible = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").invincible
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
local AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService").AnalyticsService
local RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher").RocketLauncher
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
local TutorialHooks = TS.import(script, game:GetService("ServerScriptService"), "TS", "tutorial", "TutorialHooks").TutorialHooks
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local RISK_RAMP_DURATION = _RocketGameConfig.RISK_RAMP_DURATION
local MULTIPLIER_TICK_RATE = _RocketGameConfig.MULTIPLIER_TICK_RATE
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local MULTIPLIER_PER_STUD = _RocketGameConfig.MULTIPLIER_PER_STUD
local EXPLOSION_VIEW_DELAY = _RocketGameConfig.EXPLOSION_VIEW_DELAY
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local resistanceRiskParams = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ResistanceCurve").resistanceRiskParams
-- ── Game tuning ───────────────────────────────────────────────────────────────
local MAX_RISK = 0.8
local TICK_RATE = 0.5
-- Lot de consolation sur une perte (explosion sans claim) : baseCash / 3 —
-- FORFAITAIRE, sans le multiplicateur. Pas de popup de fin.
local LOSS_CONSOLATION_DIVISOR = 3
-- "Go Home" (retour à la base après un claim) : délai avant de reposer le rig sur le pad,
-- le temps que la caméra soit revenue au joueur.
local GO_HOME_RESET_DELAY = 0.6
local EXPLOSION_SOUND_ID = AudioConfig.sfx.explosion.id
local EXPLOSION_SOUND_VOLUME = AudioConfig.sfx.explosion.volume
local EXPLOSION_SOUND_ROLLOFF = 120
-- Alias — keeps the risk/progress math unchanged while sourcing the value from the shared config
local TOTAL_DURATION = RISK_RAMP_DURATION
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
-- EaseInQuad: risk starts near 0 and accelerates — reaches MAX_RISK at TOTAL_DURATION seconds
local function getRisk(timeHeld)
	local t = math.min(timeHeld / TOTAL_DURATION, 1)
	return MAX_RISK * (t * t)
end
-- Effective per-tick risk at `timeHeld` for a resistance profile. Zero inside the
-- safe window; outside it the base curve ramps from the window's end, scaled down.
local function riskAt(timeHeld, params)
	if timeHeld <= params.safeWindow then
		return 0
	end
	return getRisk(timeHeld - params.safeWindow) * params.riskScale
end
-- ── Explosion-time preload ──────────────────────────────────────────────────────
-- Guard on the precompute loop. At max resistance the risk floor is ×0.25 (not
-- zero — RESISTANCE_MAX_REDUCTION = 0.75) and the safe window guarantees ~8s
-- before the first roll (RESISTANCE_MAX_SAFE_WINDOW), so a run can last a while —
-- but never forever. 2000 ticks (1000s) only guards against a pathological
-- never-ending loop; no real hold reaches it.
local EXPLOSION_ROLL_CAP = 2000
-- Precompute, once at launch, the exact moment the rocket will explode by running the
-- SAME per-tick risk roll the live loop uses — but all at once, up front. This "loads"
-- the explosion time so the run can fire the explosion at that precise scheduled moment
-- instead of re-rolling RNG every tick and discovering it late (action/event delay).
-- The probability distribution is identical to the live per-tick model. Returns the
-- time-held (seconds, tick-aligned) at which the rocket explodes.
local function rollExplosionTime(params)
	local timeHeld = 0
	for i = 0, EXPLOSION_ROLL_CAP - 1 do
		timeHeld += TICK_RATE
		if math.random() < riskAt(timeHeld, params) then
			return timeHeld
		end
	end
	return timeHeld
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
	local baseCash = PlayerProgressionService:get(player, "EffectiveBaseCash")
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
	-- Preload the "chance" at launch: precompute the exact instant the rocket will
	-- explode (tick-aligned, same distribution as the old per-tick roll). The run then
	-- fires the explosion at this scheduled moment — no per-tick RNG, no discovery delay.
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
	local _result = scripted
	if _result ~= nil then
		_result = _result.speedFactor
	end
	local _condition = _result
	if _condition == nil then
		_condition = 1
	end
	RocketLauncher:launch(room, rocketSpeed * _condition)
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
	local claimConn = Events.ClaimButtonEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive or claimed then
			return nil
		end
		claimed = true
		claimedMultiplier = currentMultiplier
		Events.ClaimAcceptedEvent:FireClient(player, claimedMultiplier)
		local _result_1 = scripted
		if _result_1 ~= nil then
			_result_1.onClaim()
		end
		-- Analytics: claim locked (custom counter + funnel step 2 + onboarding step 3).
		AnalyticsService:custom(player, "RunClaimed", claimedMultiplier)
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
		local earned = math.floor(baseCash * claimedMultiplier)
		-- exploded=false : c'est le client qui ramène la caméra au joueur (retour à la base).
		Events.GameResultEvent:FireClient(player, false, earned, claimedMultiplier)
		EndGameButtonModule:enter(player, "released", baseCash, claimedMultiplier, earned, 1)
		-- Analytics: win banked early (Go Home) — funnel step 3 + custom counter.
		AnalyticsService:runStep(player, runId, 3, "Banked")
		AnalyticsService:custom(player, "RunGoHome", earned)
		-- On laisse la caméra revenir au joueur avant de reposer le rig sur le pad
		-- (sinon la fusée se téléporterait sous les yeux du joueur), puis la fusée est
		-- réinstanciée neuve sur le pad — exactement comme après une explosion.
		task.delay(GO_HOME_RESET_DELAY, function()
			RocketLauncher:reset(room)
			RocketPlacer:place(room)
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
					RocketLauncher:reset(room)
					RocketPlacer:place(room)
					local earned = math.floor(baseCash * claimedMultiplier)
					-- exploded=true : côté client PlayerKilledEvent gère la caméra (pas de double retour).
					Events.GameResultEvent:FireClient(player, true, earned, claimedMultiplier)
					EndGameButtonModule:enter(player, "killed", baseCash, claimedMultiplier, earned, 1)
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
					RocketLauncher:reset(room)
					RocketPlacer:place(room)
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
