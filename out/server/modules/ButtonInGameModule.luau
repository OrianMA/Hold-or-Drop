-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local ButtonSessionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "ButtonSessionService").ButtonSessionService
local UiService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "UiService").UiService
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ReplicatedStorage = _services.ReplicatedStorage
local TweenService = _services.TweenService
local Workspace = _services.Workspace
local invincible = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig").invincible
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
local ConfettiBurst = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ConfettiBurst").ConfettiBurst
local RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher").RocketLauncher
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local RISK_RAMP_DURATION = _RocketGameConfig.RISK_RAMP_DURATION
local MULTIPLIER_TICK_RATE = _RocketGameConfig.MULTIPLIER_TICK_RATE
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local MULTIPLIER_PER_STUD = _RocketGameConfig.MULTIPLIER_PER_STUD
local EXPLOSION_VIEW_DELAY = _RocketGameConfig.EXPLOSION_VIEW_DELAY
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- ── Game tuning ───────────────────────────────────────────────────────────────
local MAX_RISK = 0.8
local TICK_RATE = 0.5
-- Lot de consolation sur une perte (explosion sans claim / parade ratée) :
-- baseCash / 3 — FORFAITAIRE, sans le multiplicateur. Pas de popup de fin.
local LOSS_CONSOLATION_DIVISOR = 3
local KNOCKBACK_DISTANCE = 15
local KNOCKBACK_DURATION = 0.5
-- Small enough that bystanders standing near the button aren't in range, but
-- large enough to cover the assigned player teleported just above the button.
-- Roblox's default explosion handles the fling — we just keep the radius tight
-- so the BlastPressure stays scoped to a single character.
local EXPLOSION_BLAST_RADIUS = 12
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
-- ── Resistance → risk model ──────────────────────────────────────────────────────
-- Resistance is a 0..100 shop stat (see ShopConfig). It reshapes the explosion risk
-- in two independent ways, so a higher resistance both lasts longer on average AND
-- gets a longer guaranteed-safe head start:
--   • riskScale  — scales the WHOLE risk curve down. FRONT-loaded (reduction =
--     MAX_REDUCTION × (1 − (1 − n)^CURVE)): the first levels cut risk hugely, the
--     last levels barely move it. This is what makes level 20 already ~20s average.
--   • safeWindow — seconds at the start where risk is forced to 0. BACK-loaded
--     (n^CURVE × MAX): it stays ~0 until high resistance and only reaches ~15s near
--     level 100 — so a max rocket can't blow before ~15s, while a level-20 rocket
--     still has a very small early chance.
-- After the safe window the base curve ramps from 0 (shifted by safeWindow), so the
-- post-window climb is gentle. At resistance 0 both terms are neutral → identical to
-- the un-upgraded curve.
local RESISTANCE_MAX_LEVEL = 100
local RESISTANCE_MAX_REDUCTION = 0.99
local RESISTANCE_REDUCTION_CURVE = 12
local RESISTANCE_MAX_SAFE_WINDOW = 15
local RESISTANCE_SAFE_WINDOW_CURVE = 2.5
local function resistanceRiskParams(resistance)
	local n = math.clamp(resistance / RESISTANCE_MAX_LEVEL, 0, 1)
	local reduction = RESISTANCE_MAX_REDUCTION * (1 - (1 - n) ^ RESISTANCE_REDUCTION_CURVE)
	local safeWindow = n ^ RESISTANCE_SAFE_WINDOW_CURVE * RESISTANCE_MAX_SAFE_WINDOW
	return {
		riskScale = 1 - reduction,
		safeWindow = safeWindow,
	}
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
-- Guard on the precompute loop. At max resistance the risk floor is tiny and the
-- safe window pushes the first roll to ~15s, so a run can last minutes — but never
-- forever. 2000 ticks (1000s) only guards against a pathological never-ending loop;
-- no real hold reaches it.
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
-- Triggers a 3D explosion at `pos`: visual and sound fire together from the
-- same replication batch, so clients see and hear them simultaneously.
-- blastPressure = 0 for parry (visual-only), non-zero for lethal explosions.
--
-- BlastRadius is intentionally tight (EXPLOSION_BLAST_RADIUS): the radius
-- gates *both* visual size and the BlastPressure reach. Keeping it small means
-- the fling is naturally scoped to the player anchored on top of the button —
-- bystanders standing a few studs away aren't inside the bubble and are left
-- alone, no manual filtering required.
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
local function triggerExplosionAt(pos, blastPressure)
	playExplosionSoundAt(pos)
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = EXPLOSION_BLAST_RADIUS
	explosion.BlastPressure = blastPressure
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = Workspace
end
-- ── Public API ────────────────────────────────────────────────────────────────
-- Used by the ButtonMenu Quit flow — release/explosion/parry endings transition
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
	local buttonModel = room.buttonModel
	-- EffectiveBaseCash already folds in every money multiplier (rebirth + money
	-- game-pass tier + community), additively. Read once — held for the session so
	-- a mid-run boost change can't alter an in-progress hold.
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
	-- Preload the "chance" at launch: precompute the exact instant the rocket will
	-- explode (tick-aligned, same distribution as the old per-tick roll). The run then
	-- fires the explosion at this scheduled moment — no per-tick RNG, no discovery delay.
	-- invincible ⇒ never explodes.
	local explosionAt = if invincible then math.huge else rollExplosionTime(riskParams)
	Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
	Events.RiskUpdateEvent:FireClient(player, 0)
	-- La fusée décolle dès le début du gameplay, à une vitesse pilotée par le stat
	-- Rocket Speed du joueur (1 = rampe). Sa vélocité pilote ensuite le multiplicateur.
	RocketLauncher:launch(room, rocketSpeed)
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
			-- Avance jusqu'au prochain rafraîchissement de barre sans jamais dépasser
			-- l'instant d'explosion précalculé → l'explosion tombe pile à `explosionAt`.
			local nextStep = math.min(timeHeld + TICK_RATE, explosionAt)
			task.wait(nextStep - timeHeld)
			if not isActive then
				break
			end
			timeHeld = nextStep
			-- Resistance reshapes the effective risk (scale + safe window) — same
			-- profile used to precompute explosionAt, so the bar matches the outcome.
			local risk = riskAt(timeHeld, riskParams)
			Events.RiskUpdateEvent:FireClient(player, risk)
			if not invincible and timeHeld >= explosionAt then
				isActive = false
				claimConn:Disconnect()
				if claimed then
					-- Le joueur a claim avant l'explosion → gain GARANTI au multiplicateur
					-- verrouillé. La fusée explose (spectacle), puis le payout se fait au
					-- claimedMultiplier EXACT — pas de fenêtre de parade, aucune pénalité.
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
					return nil
				end
				-- Pas de claim à temps : l'explosion tombe → dernière chance en parade (parry).
				Events.ButtonExplodedEvent:FireClient(player)
				-- 0.2s de grâce avant la fenêtre de parade (le client attend 0.2s aussi).
				task.wait(0.2)
				do
					local character = player.Character
					local _result = character
					if _result ~= nil then
						_result = _result:FindFirstChild("HumanoidRootPart")
					end
					local hrp = _result
					local _humanoid = character
					if _humanoid ~= nil then
						_humanoid = _humanoid:FindFirstChildOfClass("Humanoid")
					end
					local humanoid = _humanoid
					-- Capture button reference before session is cleared
					local buttonPart = room.buttonPart
					-- Deregister button immediately (avoids WaitForChild blocking the UI)
					ButtonSessionService:cleanup(player)
					-- Freeze movement for the parry window
					local _result_1 = humanoid
					if _result_1 ~= nil then
						_result_1 = _result_1.WalkSpeed
					end
					local _condition = _result_1
					if _condition == nil then
						_condition = 16
					end
					local origWalkSpeed = _condition
					local _result_2 = humanoid
					if _result_2 ~= nil then
						_result_2 = _result_2.JumpPower
					end
					local _condition_1 = _result_2
					if _condition_1 == nil then
						_condition_1 = 50
					end
					local origJumpPower = _condition_1
					local _result_3 = humanoid
					if _result_3 ~= nil then
						_result_3 = _result_3.JumpHeight
					end
					local _condition_2 = _result_3
					if _condition_2 == nil then
						_condition_2 = 7.2
					end
					local origJumpHeight = _condition_2
					if humanoid then
						humanoid.WalkSpeed = 0
						humanoid.JumpPower = 0
						humanoid.JumpHeight = 0
					end
					local isPerfectParry = false
					local parryConn
					parryConn = Events.PerfectParryEvent.OnServerEvent:Connect(function(p)
						if p ~= player then
							return nil
						end
						isPerfectParry = true
						parryConn:Disconnect()
					end)
					task.wait(0.5)
					parryConn:Disconnect()
					if isPerfectParry then
						RocketLauncher:reset(room)
						if hrp then
							hrp.Anchored = true
						end
						if buttonPart then
							triggerExplosionAt(buttonPart.Position, 0)
						end
						-- Trigger sparkle effect on the parrying player's client
						Events.PerfectParryEffectEvent:FireClient(player)
						ConfettiBurst:play(buttonModel)
						if hrp and buttonPart then
							local rawDir = Vector3.new(hrp.Position.X - buttonPart.Position.X, 0, hrp.Position.Z - buttonPart.Position.Z)
							local dir = if rawDir.Magnitude > 0 then rawDir.Unit else Vector3.new(0, 0, 1)
							local _cFrame = hrp.CFrame
							local _arg0 = dir * KNOCKBACK_DISTANCE
							local targetCFrame = _cFrame + _arg0
							local tween = TweenService:Create(hrp, TweenInfo.new(KNOCKBACK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								CFrame = targetCFrame,
							})
							tween:Play()
							task.wait(KNOCKBACK_DURATION)
						end
						if hrp then
							hrp.Anchored = false
						end
						task.wait(0.5)
						if humanoid then
							humanoid.WalkSpeed = origWalkSpeed
							humanoid.JumpPower = origJumpPower
							humanoid.JumpHeight = origJumpHeight
						end
						local earned = math.floor(baseCash * currentMultiplier)
						Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
						EndGameButtonModule:enter(player, "released", baseCash, currentMultiplier, earned, 1)
					else
						-- Perte : la FUSÉE explose, pas le joueur. Pas de fling, pas de mort.
						-- explode() stoppe lui-même l'ascension après avoir capturé sa vitesse,
						-- pour que les débris conservent l'élan vers le haut (la fusée continue
						-- de monter en explosant) avant que la gravité ne les rattrape.
						local rocketPos = room.movableModel:GetPivot().Position
						RocketLauncher:explode(room)
						playExplosionSoundAt(rocketPos)
						-- Le joueur reste en vie : on lui rend sa mobilité (figée pendant la fenêtre).
						if hrp then
							hrp.Anchored = false
						end
						if humanoid then
							humanoid.WalkSpeed = origWalkSpeed
							humanoid.JumpPower = origJumpPower
							humanoid.JumpHeight = origJumpHeight
						end
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
					end
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
