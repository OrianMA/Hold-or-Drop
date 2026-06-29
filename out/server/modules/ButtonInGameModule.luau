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
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local RISK_RAMP_DURATION = _RocketGameConfig.RISK_RAMP_DURATION
local MULTIPLIER_TICK_RATE = _RocketGameConfig.MULTIPLIER_TICK_RATE
local STARTING_MULTIPLIER = _RocketGameConfig.STARTING_MULTIPLIER
local MULTIPLIER_START_INCREMENT = _RocketGameConfig.MULTIPLIER_START_INCREMENT
local MULTIPLIER_INCREMENT_GROWTH = _RocketGameConfig.MULTIPLIER_INCREMENT_GROWTH
local EXPLOSION_VIEW_DELAY = _RocketGameConfig.EXPLOSION_VIEW_DELAY
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- ── Game tuning ───────────────────────────────────────────────────────────────
local MAX_RISK = 0.8
local TICK_RATE = 0.5
local LOOSE_WIN_MULTIPLIER = 0.3
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
-- ── Explosion-time preload ──────────────────────────────────────────────────────
-- Safety cap on the precompute loop. Risk plateaus at MAX_RISK once timeHeld passes
-- TOTAL_DURATION, so even at max safety an explosion is statistically certain within a
-- few seconds — this only guards against a pathological never-ending loop.
local EXPLOSION_ROLL_CAP = 2000
-- Precompute, once at launch, the exact moment the rocket will explode by running the
-- SAME per-tick risk roll the live loop used to do — but all at once, up front. This
-- "loads" the explosion time so the run can fire the explosion at that precise scheduled
-- moment instead of re-rolling RNG every tick and discovering it late (action/event delay).
-- The probability distribution is identical to the old per-tick model, so game balance is
-- unchanged. Returns the time-held (seconds, tick-aligned) at which the rocket explodes.
local function rollExplosionTime(safety)
	local timeHeld = 0
	for i = 0, EXPLOSION_ROLL_CAP - 1 do
		timeHeld += TICK_RATE
		local risk = getRisk(timeHeld) * (1 - safety)
		if math.random() < risk then
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
	-- Safety (0..0.70 with the pass) scales the explosion risk down. Read once.
	local safety = PlayerProgressionService:get(player, "AdditionalSecurity")
	-- Démarre à 1.00x puis grimpe de façon accélérée (très lent au début, de plus en
	-- plus vite — voir RocketGameConfig). Le niveau Multiplier du joueur n'est pas
	-- encore pris en compte.
	local currentMultiplier = STARTING_MULTIPLIER
	local multiplierIncrement = MULTIPLIER_START_INCREMENT
	local isActive = true
	-- Preload the "chance" at launch: precompute the exact instant the rocket will
	-- explode (tick-aligned, same distribution as the old per-tick roll). The run then
	-- fires the explosion at this scheduled moment — no per-tick RNG, no discovery delay.
	-- invincible ⇒ never explodes.
	local explosionAt = if invincible then math.huge else rollExplosionTime(safety)
	Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
	Events.RiskUpdateEvent:FireClient(player, 0)
	-- La fusée décolle dès le début du gameplay. speedFactor = 1 pour l'instant ;
	-- il sera dérivé du multiplier level plus tard.
	RocketLauncher:launch(room)
	local releaseConn
	releaseConn = Events.ReleaseButtonEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive then
			return nil
		end
		isActive = false
		releaseConn:Disconnect()
		-- Win : la fusée s'arrête et revient au pad pour la prochaine partie.
		RocketLauncher:reset(room)
		local earned = math.floor(baseCash * currentMultiplier)
		Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
		ConfettiBurst:play(buttonModel)
		EndGameButtonModule:enter(player, "released", baseCash, currentMultiplier, earned, 1)
	end)
	-- ── Boucle multiplier ─────────────────────────────────────────────────────
	-- Croissance accélérée : chaque tick on ajoute `multiplierIncrement`, et cet
	-- incrément grossit lui-même à chaque tick → très lent au début, de plus en plus
	-- rapide. Indépendant de la boucle risque.
	task.spawn(function()
		while isActive do
			task.wait(MULTIPLIER_TICK_RATE)
			if not isActive then
				break
			end
			currentMultiplier += multiplierIncrement
			multiplierIncrement += MULTIPLIER_INCREMENT_GROWTH
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
			-- Safety reduces the effective risk: at 50% safety the ceiling halves.
			local risk = getRisk(timeHeld) * (1 - safety)
			Events.RiskUpdateEvent:FireClient(player, risk)
			if not invincible and timeHeld >= explosionAt then
				isActive = false
				releaseConn:Disconnect()
				Events.ButtonExplodedEvent:FireClient(player)
				-- 0.2s grace period — player can still release to cancel the explosion
				local cancelledByPlayer = false
				local gracePeriodConn
				gracePeriodConn = Events.ReleaseButtonEvent.OnServerEvent:Connect(function(p)
					if p ~= player then
						return nil
					end
					cancelledByPlayer = true
					gracePeriodConn:Disconnect()
				end)
				task.wait(0.2)
				gracePeriodConn:Disconnect()
				if cancelledByPlayer then
					RocketLauncher:reset(room)
					local earned = math.floor(baseCash * currentMultiplier)
					Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
					ConfettiBurst:play(buttonModel)
					EndGameButtonModule:enter(player, "released", baseCash, currentMultiplier, earned, 1)
				else
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
						RocketLauncher:stop(room)
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
						-- On laisse l'explosion se jouer avant de ramener la fusée + ouvrir le payout.
						task.wait(EXPLOSION_VIEW_DELAY)
						RocketLauncher:reset(room)
						local earned = math.floor(baseCash * LOOSE_WIN_MULTIPLIER * currentMultiplier)
						Events.GameResultEvent:FireClient(player, true, earned, currentMultiplier)
						EndGameButtonModule:enter(player, "killed", baseCash, currentMultiplier, earned, LOOSE_WIN_MULTIPLIER)
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
