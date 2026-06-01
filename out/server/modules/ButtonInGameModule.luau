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
local _ButtonGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ButtonGameConfig")
local RISK_RAMP_DURATION = _ButtonGameConfig.RISK_RAMP_DURATION
local MULTIPLIER_TICK_RATE = _ButtonGameConfig.MULTIPLIER_TICK_RATE
local STARTING_MULTIPLIER = _ButtonGameConfig.STARTING_MULTIPLIER
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
local EXPLOSION_KILL_PRESSURE = 180000
local EXPLOSION_SOUND_ID = "rbxassetid://139771888058836"
local EXPLOSION_SOUND_VOLUME = 0.8
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
-- Triggers a 3D explosion at `pos`: visual and sound fire together from the
-- same replication batch, so clients see and hear them simultaneously.
-- blastPressure = 0 for parry (visual-only), non-zero for lethal explosions.
--
-- BlastRadius is intentionally tight (EXPLOSION_BLAST_RADIUS): the radius
-- gates *both* visual size and the BlastPressure reach. Keeping it small means
-- the fling is naturally scoped to the player anchored on top of the button —
-- bystanders standing a few studs away aren't inside the bubble and are left
-- alone, no manual filtering required.
local function triggerExplosionAt(pos, blastPressure)
	-- Sound cloned from the pre-buffered template — no CDN fetch on the client.
	-- Parented to Terrain via an Attachment for proper 3D rolloff.
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = pos
	local sound = explosionSoundTemplate:Clone()
	sound.Parent = attachment
	sound:Play()
	sound.Ended:Connect(function()
		return attachment:Destroy()
	end)
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
	-- BaseCash + Multiplier now live on the player (PlayerProgressionService),
	-- not on the button. Read once at game start — held for the whole session.
	local baseCash = PlayerProgressionService:get(player, "BaseCash")
	local multiplierPerSecond = PlayerProgressionService:get(player, "Multiplier")
	-- Démarre à 1x (paiement de base) puis grimpe de `multiplierPerSecond`/s.
	local currentMultiplier = STARTING_MULTIPLIER
	local isActive = true
	Events.BaseCashEvent:FireClient(player, baseCash)
	Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
	Events.RiskUpdateEvent:FireClient(player, 0)
	local releaseConn
	releaseConn = Events.ReleaseButtonEvent.OnServerEvent:Connect(function(p)
		if p ~= player or not isActive then
			return nil
		end
		isActive = false
		releaseConn:Disconnect()
		local earned = baseCash * currentMultiplier
		Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
		ConfettiBurst:play(buttonModel)
		EndGameButtonModule:enter(player, "released", baseCash, currentMultiplier, earned, 1)
	end)
	-- ── Boucle multiplier ─────────────────────────────────────────────────────
	-- Increment plat : chaque seconde, currentMultiplier += multiplierPerSecond
	-- (la valeur Multiplier du joueur). Indépendant de la boucle risque.
	task.spawn(function()
		while isActive do
			task.wait(MULTIPLIER_TICK_RATE)
			if not isActive then
				break
			end
			currentMultiplier += multiplierPerSecond
			Events.MultiplierUpdateEvent:FireClient(player, currentMultiplier)
		end
	end)
	-- ── Boucle risque & progression ───────────────────────────────────────────
	-- Tourne à TICK_RATE pour les checks d'explosion, le risque et la progress bar.
	task.spawn(function()
		local timeHeld = 0
		while isActive do
			task.wait(TICK_RATE)
			if not isActive then
				break
			end
			timeHeld += TICK_RATE
			local risk = getRisk(timeHeld)
			Events.RiskUpdateEvent:FireClient(player, risk)
			local progress = math.min(timeHeld / TOTAL_DURATION, 1)
			Events.ProgressUpdateEvent:FireClient(player, progress)
			if not invincible and math.random() < risk then
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
					local earned = baseCash * currentMultiplier
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
						local earned = baseCash * currentMultiplier
						Events.GameResultEvent:FireClient(player, false, earned, currentMultiplier)
						EndGameButtonModule:enter(player, "released", baseCash, currentMultiplier, earned, 1)
					else
						if hrp then
							hrp.Anchored = false
						end
						if character then
							for _, desc in character:GetDescendants() do
								if desc:IsA("Motor6D") then
									desc.Enabled = false
								end
							end
						end
						if buttonPart then
							triggerExplosionAt(buttonPart.Position, EXPLOSION_KILL_PRESSURE)
						end
						if humanoid then
							humanoid.Health = 0
						end
						Events.PlayerKilledEvent:FireClient(player)
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
