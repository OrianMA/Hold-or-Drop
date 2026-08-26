-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local RunService = _services.RunService
-- ── Petite pluie d'icônes 2D (particules = ImageLabels) ─────────────────────────
--
-- Jouée en même temps que le flash doré "CRITICAL CLAIM" (ClaimFlashText) : une
-- poignée d'images tombent du haut de l'écran, dérivent en tournant doucement et
-- se dissolvent en bas. Purement client, purement visuel.
--
-- `play`/`preload` acceptent une IMAGE : la même simulation sert aussi la pluie
-- jouée à l'accomplissement d'une quête (§6.26), qui doit être exactement le même
-- effet avec une autre icône. Sans argument, c'est l'icône du Critical Claim.
--
-- Même approche que MoneyBurst : pas de ParticleEmitter, c'est de la 2D écran, donc
-- une mini simulation en pixels dans RenderStepped.
-- Icône dorée du Critical Claim. Exportée : l'escalade de paiement (PayoutTiers,
-- §6.4) s'en sert pour sa pluie d'or, et il ne doit y avoir qu'une source de vérité.
local RAIN_IMAGE = "rbxassetid://13506500866"
-- ── Tuning ──────────────────────────────────────────────────────────────────────
-- Les valeurs en pixels sont exprimées pour un écran de REFERENCE_HEIGHT px et
-- remises à l'échelle du viewport réel (mobile compris).
local REFERENCE_HEIGHT = 900
local PARTICLE_COUNT = 40
local ICON_SIZE = 60
local ICON_SIZE_JITTER = 0.3
-- Plafond de gouttes VIVANTES, tous appels confondus. L'escalade de paiement
-- (PayoutTiers, §6.4) empile jusqu'à trois pluies en une seconde : sans ce garde-fou
-- on ferait tomber 150+ ImageLabels simulés par frame sur mobile.
local MAX_LIVE_DROPS = 70
-- Les icônes ne sont pas lâchées par un timer : elles démarrent réparties dans une
-- bande AU-DESSUS de l'écran, donc elles entrent dans le champ les unes après les
-- autres — c'est ce qui fait la pluie plutôt qu'une salve.
-- C'est aussi ce qui règle la DURÉE de la pluie : plus la bande est haute, plus les
-- dernières icônes entrent tard dans le champ.
local SPAWN_BAND = 1600
local FALL_SPEED_MIN = 340
local FALL_SPEED_MAX = 620
local GRAVITY = 300
local DRIFT_MAX = 70
local SPIN_MAX = 110
local SWAY_AMPLITUDE = 55
local SWAY_SPEED_MIN = 1.5
local SWAY_SPEED_MAX = 3.5
local FADE_START_Y = 0.68
local MAX_LIFETIME = 9
local LABEL_NAME = "CriticalRainIcon"
local Z_INDEX = 55
-- ── Simulation ──────────────────────────────────────────────────────────────────
local drops = {}
local stepConn
local function getScreenGui()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local _found = playerGui
	if _found ~= nil then
		_found = _found:FindFirstChild("InGameUI")
	end
	local found = _found
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("ScreenGui")
	end
	return if _result then found else nil
end
local function destroyDrop(index)
	drops[index + 1].label:Destroy()
	local _index = index
	table.remove(drops, _index + 1)
end
local function step(dt)
	-- dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les icônes.
	local delta = math.min(dt, 1 / 20)
	local screenGui = getScreenGui()
	local viewportHeight = if screenGui ~= nil then screenGui.AbsoluteSize.Y else 0
	for i = #drops - 1, 0, -1 do
		local drop = drops[i + 1]
		drop.age += delta
		drop.vy += GRAVITY * drop.scale * delta
		-- Balancement latéral façon feuille qui tombe.
		drop.swayPhase += drop.swaySpeed * delta
		drop.vx += math.sin(drop.swayPhase) * SWAY_AMPLITUDE * drop.scale * delta
		drop.x += drop.vx * delta
		drop.y += drop.vy * delta
		drop.rotation += drop.spin * delta
		local label = drop.label
		label.Position = UDim2.new(0, drop.x, 0, drop.y)
		label.Rotation = drop.rotation
		-- Dissolution dans le bas de l'écran : l'icône ne disparaît jamais d'un coup.
		if viewportHeight > 0 then
			local fadeFrom = viewportHeight * FADE_START_Y
			if drop.y > fadeFrom then
				label.ImageTransparency = math.clamp((drop.y - fadeFrom) / (viewportHeight - fadeFrom), 0, 1)
			end
		end
		local belowScreen = viewportHeight > 0 and drop.y > viewportHeight + drop.size
		if belowScreen or drop.age >= MAX_LIFETIME then
			destroyDrop(i)
		end
	end
	if #drops == 0 then
		local _result = stepConn
		if _result ~= nil then
			_result:Disconnect()
		end
		stepConn = nil
	end
end
-- ── API ─────────────────────────────────────────────────────────────────────────
local CriticalRain = {
	preload = function(self, image)
		if image == nil then
			image = RAIN_IMAGE
		end
		task.spawn(function()
			local probe = Instance.new("ImageLabel")
			probe.Image = image
			pcall(function()
				return ContentProvider:PreloadAsync({ probe })
			end)
			probe:Destroy()
		end)
	end,
	play = function(self, image, options)
		if image == nil then
			image = RAIN_IMAGE
		end
		local screenGui = getScreenGui()
		if not screenGui then
			return nil
		end
		local viewport = screenGui.AbsoluteSize
		if viewport.X == 0 or viewport.Y == 0 then
			return nil
		end
		local scale = viewport.Y / REFERENCE_HEIGHT
		local _result = options
		if _result ~= nil then
			_result = _result.band
		end
		local _condition = _result
		if _condition == nil then
			_condition = SPAWN_BAND
		end
		local band = _condition
		local _result_1 = options
		if _result_1 ~= nil then
			_result_1 = _result_1.zIndex
		end
		local _condition_1 = _result_1
		if _condition_1 == nil then
			_condition_1 = Z_INDEX
		end
		local zIndex = _condition_1
		-- Le plafond ÉVICTE les plus anciennes gouttes plutôt que de tronquer la
		-- nouvelle pluie : pendant l'escalade de paiement, c'est toujours le DERNIER
		-- palier (le plus gros) qui doit s'afficher en entier — tronquer ferait
		-- décroître l'effet à mesure que le gain grossit, exactement l'inverse du but.
		local _result_2 = options
		if _result_2 ~= nil then
			_result_2 = _result_2.count
		end
		local _condition_2 = _result_2
		if _condition_2 == nil then
			_condition_2 = PARTICLE_COUNT
		end
		local count = math.min(_condition_2, MAX_LIVE_DROPS)
		if count <= 0 then
			return nil
		end
		local overflow = #drops + count - MAX_LIVE_DROPS
		do
			local i = 0
			local _shouldIncrement = false
			while true do
				if _shouldIncrement then
					i += 1
				else
					_shouldIncrement = true
				end
				if not (i < overflow) then
					break
				end
				destroyDrop(0)
			end
		end
		do
			local i = 0
			local _shouldIncrement = false
			while true do
				if _shouldIncrement then
					i += 1
				else
					_shouldIncrement = true
				end
				if not (i < count) then
					break
				end
				local sizeJitter = 1 + (math.random() * 2 - 1) * ICON_SIZE_JITTER
				local size = ICON_SIZE * sizeJitter * scale
				-- X réparti en colonnes + bruit : la pluie couvre la largeur sans paquets.
				local x = ((i + math.random()) / count) * viewport.X
				local y = -size - math.random() * band * scale
				local label = Instance.new("ImageLabel")
				label.Name = LABEL_NAME
				label.Image = image
				label.BackgroundTransparency = 1
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.Position = UDim2.new(0, x, 0, y)
				label.Size = UDim2.new(0, size, 0, size)
				label.Rotation = math.random() * 360
				label.ZIndex = zIndex
				label.Active = false
				label.Parent = screenGui
				local _arg0 = {
					label = label,
					x = x,
					y = y,
					vx = (math.random() * 2 - 1) * DRIFT_MAX * scale,
					vy = (FALL_SPEED_MIN + math.random() * (FALL_SPEED_MAX - FALL_SPEED_MIN)) * scale,
					size = size,
					scale = scale,
					rotation = label.Rotation,
					spin = (math.random() * 2 - 1) * SPIN_MAX,
					swayPhase = math.random() * math.pi * 2,
					swaySpeed = SWAY_SPEED_MIN + math.random() * (SWAY_SPEED_MAX - SWAY_SPEED_MIN),
					age = 0,
				}
				table.insert(drops, _arg0)
			end
		end
		if not stepConn then
			stepConn = RunService.RenderStepped:Connect(step)
		end
	end,
	clear = function(self)
		for _, drop in drops do
			drop.label:Destroy()
		end
		table.clear(drops)
		local _result = stepConn
		if _result ~= nil then
			_result:Disconnect()
		end
		stepConn = nil
	end,
}
return {
	RAIN_IMAGE = RAIN_IMAGE,
	CriticalRain = CriticalRain,
}
