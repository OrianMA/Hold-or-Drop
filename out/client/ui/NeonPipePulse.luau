-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Réaction d'achat dans les tubes néon : à chaque achat au shop, un petit segment
-- de couleur file le long des DEUX tubes du joueur, du shop jusqu'au bouton — comme
-- si l'amélioration partait physiquement vers le bouton.
--
-- Plusieurs achats = plusieurs segments : chaque amélioration lance sa propre
-- animation même si d'autres sont déjà en cours, et les achats quasi simultanés sont
-- libérés en file avec un petit décalage (QUEUE_DELAY) pour les afficher proprement.
--
-- 100 % client / présentation (cf. AudioVisualizer §6.11) : le serveur se contente
-- d'incrémenter l'attribut `Pulse` du dossier Environment/NeonPipe/P{n}
-- (NeonPipeColors.pulse). On écoute cet attribut et on anime localement — aucune
-- couleur n'est répliquée, aucun RemoteEvent.
local ENVIRONMENT = "Environment"
local NEON_PIPE = "NeonPipe"
local PULSE_ATTR = "Pulse"
local TUBE_NAMES = { "Right", "Left" }
-- Effet d'arrivée au bouton (P{n} → PlayerZones/P{n}/ButtonModel). Le segment qui
-- atteint le bouton allume une gerbe d'étincelles + un petit son électrique.
local PLAYER_ZONES = "PlayerZones"
local BUTTON_MODEL = "ButtonModel"
local MOVABLE_MODEL = "MovableModel"
local PARTICLE_PART = "ParticleEmmiter"
local PARTICLE_EMITTER = "UpgradeButtonParticles"
local BUTTON_PART = "ButtonPart"
local PARTICLE_DURATION = 1.2
-- --- réglages -------------------------------------------------------------
local SEGMENT_LENGTH = 5
local TRAVEL_TIME = 5
local LIGHT_FACTOR = 0.85
local TRAIL_FADE = true
local QUEUE_DELAY = 0.35
-- --------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
-- Un segment en vol : sa seule donnée est sa progression 0..1 le long du tube.
-- Un tube physique (Right/Left) : ses parts ordonnées shop → bouton, et les index
-- colorés à la frame précédente (pour les restaurer efficacement).
-- L'état d'animation d'une salle : les deux tubes, la couleur de base (du slot) et
-- sa version claire, la liste des segments en vol (partagée par les deux tubes pour
-- rester synchrones), et la file d'attente (pending + minuterie de décalage).
local roomStates = {}
local activeRooms = {}
local lastPulse = {}
local weightByIndex = {}
local shopPosition = Vector3.zero
local function lighten(c)
	return c:Lerp(WHITE, LIGHT_FACTOR)
end
-- Centroïde des parts du Shop : sert de point de départ à l'ordonnancement.
local function computeShopPosition()
	local shop = Workspace:FindFirstChild("Shop")
	if shop then
		local sum = Vector3.zero
		local count = 0
		for _, d in shop:GetDescendants() do
			if d:IsA("BasePart") then
				local _sum = sum
				local _position = d.Position
				sum = _sum + _position
				count += 1
			end
		end
		if count > 0 then
			local _sum = sum
			local _arg0 = 1 / count
			return _sum * _arg0
		end
	end
	warn("NeonPipePulse: Workspace.Shop introuvable, ordonnancement depuis une extrémité arbitraire")
	return Vector3.zero
end
-- Ordonne les parts d'un tube en une chaîne shop → bouton : on démarre par la part
-- la plus proche du shop puis on enchaîne le plus proche voisin non visité. Les parts
-- sont régulièrement espacées le long d'un chemin continu, donc cette marche reconstruit
-- fidèlement le trajet (calcul fait une seule fois par tube, puis mis en cache).
local function orderTube(folder)
	local parts = {}
	for _, c in folder:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(parts, c)
		end
	end
	local n = #parts
	if n == 0 then
		return parts
	end
	local startI = 0
	local bestD = math.huge
	do
		local i = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < n) then
				break
			end
			local _position = parts[i + 1].Position
			local _shopPosition = shopPosition
			local d = (_position - _shopPosition).Magnitude
			if d < bestD then
				bestD = d
				startI = i
			end
		end
	end
	local used = {}
	do
		local i = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				i += 1
			else
				_shouldIncrement = true
			end
			if not (i < n) then
				break
			end
			used[i + 1] = false
		end
	end
	local result = {}
	local cur = startI
	used[cur + 1] = true
	local _arg0 = parts[cur + 1]
	table.insert(result, _arg0)
	do
		local s = 1
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				s += 1
			else
				_shouldIncrement = true
			end
			if not (s < n) then
				break
			end
			local bi = -1
			local bd = math.huge
			local cp = parts[cur + 1].Position
			do
				local i = 0
				local _shouldIncrement_1 = false
				while true do
					if _shouldIncrement_1 then
						i += 1
					else
						_shouldIncrement_1 = true
					end
					if not (i < n) then
						break
					end
					if used[i + 1] then
						continue
					end
					local d = (parts[i + 1].Position - cp).Magnitude
					if d < bd then
						bd = d
						bi = i
					end
				end
			end
			if bi < 0 then
				break
			end
			used[bi + 1] = true
			local _arg0_1 = parts[bi + 1]
			table.insert(result, _arg0_1)
			cur = bi
		end
	end
	return result
end
-- Résout la particule + crée le son 3D du bouton de la salle. Le nom de dossier P{n}
-- correspond 1:1 à PlayerZones/P{n}/ButtonModel. Tolère l'absence (effet ignoré).
local function resolveButtonEffect(roomName)
	local _room = Workspace:FindFirstChild(PLAYER_ZONES)
	if _room ~= nil then
		_room = _room:FindFirstChild(roomName)
	end
	local room = _room
	if not room then
		return {
			particles = nil,
			sound = nil,
		}
	end
	-- La gerbe électrique a été déplacée sur la fusée : MovableModel/ParticleEmmiter/UpgradeButtonParticles.
	local _emitter = room:FindFirstChild(MOVABLE_MODEL)
	if _emitter ~= nil then
		_emitter = _emitter:FindFirstChild(PARTICLE_PART)
		if _emitter ~= nil then
			_emitter = _emitter:FindFirstChild(PARTICLE_EMITTER)
		end
	end
	local emitter = _emitter
	local particles = if emitter ~= nil and emitter:IsA("ParticleEmitter") then emitter else nil
	-- Son électrique 3D : toujours parenté au bouton pour qu'il sonne « sur le bouton ».
	local sound
	local id = AudioConfig.sfx.buttonUpgrade.id
	local _buttonPart = room:FindFirstChild(BUTTON_MODEL)
	if _buttonPart ~= nil then
		_buttonPart = _buttonPart:FindFirstChild(BUTTON_PART)
	end
	local buttonPart = _buttonPart
	if id ~= "" and buttonPart ~= nil and buttonPart:IsA("BasePart") then
		local s = Instance.new("Sound")
		s.Name = "ButtonUpgradeSfx"
		s.SoundId = id
		s.Volume = AudioConfig.sfx.buttonUpgrade.volume
		s.Parent = buttonPart
		sound = s
	end
	return {
		particles = particles,
		sound = sound,
	}
end
-- Arrivée d'un segment au bouton : émet la particule PARTICLE_DURATION puis coupe,
-- et joue le son. Un token garde la dernière arrivée pour ne pas couper trop tôt
-- quand plusieurs segments arrivent coup sur coup.
local function fireButtonEffect(state)
	local _result = state.sound
	if _result ~= nil then
		_result:Play()
	end
	local particles = state.particles
	if not particles then
		return nil
	end
	particles.Enabled = true
	state.particleToken += 1
	local token = state.particleToken
	task.delay(PARTICLE_DURATION, function()
		if state.particleToken == token then
			particles.Enabled = false
		end
	end)
end
local function buildRoomState(folder)
	local tubes = {}
	for _, name in TUBE_NAMES do
		local sub = folder:FindFirstChild(name)
		if not sub then
			continue
		end
		local ordered = orderTube(sub)
		if #ordered == 0 then
			continue
		end
		local _arg0 = {
			ordered = ordered,
			prevLit = {},
		}
		table.insert(tubes, _arg0)
	end
	if #tubes == 0 then
		return nil
	end
	local base = tubes[1].ordered[1].Color
	local effect = resolveButtonEffect(folder.Name)
	return {
		tubes = tubes,
		base = base,
		glow = lighten(base),
		segments = {},
		pending = 0,
		sinceRelease = 0,
		particles = effect.particles,
		sound = effect.sound,
		particleToken = 0,
	}
end
-- Met `count` segments en file pour cette salle (un par amélioration achetée).
local function triggerRoom(folder, count)
	local _folder = folder
	local state = roomStates[_folder]
	if not state then
		state = buildRoomState(folder)
		if not state then
			return nil
		end
		local _folder_1 = folder
		local _state = state
		roomStates[_folder_1] = _state
	end
	-- Nouveau « burst » sur une salle au repos : ré-échantillonne la couleur du slot
	-- (les tubes sont à la couleur de base quand rien n'est en cours) et libère le
	-- premier segment immédiatement.
	if #state.segments == 0 and state.pending == 0 then
		state.base = state.tubes[1].ordered[1].Color
		state.glow = lighten(state.base)
		state.sinceRelease = QUEUE_DELAY
	end
	state.pending += count
	local _state = state
	activeRooms[_state] = true
end
-- Restaure les parts colorées à la frame précédente puis peint la nouvelle position
-- de tous les segments (poids max en cas de chevauchement).
local function renderTube(tube, state)
	for _, idx in tube.prevLit do
		tube.ordered[idx + 1].Color = state.base
	end
	table.clear(weightByIndex)
	local n = #tube.ordered
	for _, seg in state.segments do
		-- La tête avance de 0 à n+SEGMENT_LENGTH : le bandeau entre par le shop puis ressort au bouton.
		local head = math.floor(seg.progress * (n + SEGMENT_LENGTH))
		local lo = head - SEGMENT_LENGTH + 1
		if lo < 0 then
			lo = 0
		end
		local hi = head + 1
		if hi > n then
			hi = n
		end
		do
			local i = lo
			local _shouldIncrement = false
			while true do
				if _shouldIncrement then
					i += 1
				else
					_shouldIncrement = true
				end
				if not (i < hi) then
					break
				end
				-- k = distance à la tête (0 = front, côté bouton) ; la traîne (côté shop) s'estompe.
				local k = hi - 1 - i
				local w = if TRAIL_FADE then math.max(1 - k / SEGMENT_LENGTH, 0) else 1
				local _i = i
				local prev = weightByIndex[_i]
				if prev == nil or w > prev then
					local _i_1 = i
					weightByIndex[_i_1] = w
				end
			end
		end
	end
	local lit = {}
	for i, w in weightByIndex do
		tube.ordered[i + 1].Color = state.base:Lerp(state.glow, w)
		table.insert(lit, i)
	end
	tube.prevLit = lit
end
local function updateRoom(state, dt)
	-- Libère les segments en file, décalés de QUEUE_DELAY (file d'attente).
	if state.pending > 0 then
		state.sinceRelease += dt
		while state.pending > 0 and state.sinceRelease >= QUEUE_DELAY do
			local _exp = state.segments
			table.insert(_exp, {
				progress = 0,
			})
			state.pending -= 1
			state.sinceRelease -= QUEUE_DELAY
		end
	end
	-- Avance les segments ; ceux arrivés au bout (>=1) déclenchent l'effet du bouton.
	local live = {}
	for _, seg in state.segments do
		seg.progress += dt / TRAVEL_TIME
		if seg.progress < 1 then
			table.insert(live, seg)
		else
			fireButtonEffect(state)
		end
	end
	state.segments = live
	for _, tube in state.tubes do
		renderTube(tube, state)
	end
	-- Plus rien à animer ni en file → la salle est nettoyée et désactivée.
	if #state.segments == 0 and state.pending == 0 then
		local _state = state
		activeRooms[_state] = nil
	end
end
local function init()
	shopPosition = computeShopPosition()
	local _root = Workspace:FindFirstChild(ENVIRONMENT)
	if _root ~= nil then
		_root = _root:FindFirstChild(NEON_PIPE)
	end
	local root = _root
	if not root then
		warn(`NeonPipePulse: Workspace/{ENVIRONMENT}/{NEON_PIPE} introuvable`)
		return nil
	end
	for _, folder in root:GetChildren() do
		local _condition = (folder:GetAttribute(PULSE_ATTR))
		if _condition == nil then
			_condition = 0
		end
		lastPulse[folder] = _condition
		-- Le delta gère plusieurs achats traités dans la même frame serveur (la
		-- réplication d'attribut peut être coalescée : on lit le saut du compteur).
		folder:GetAttributeChangedSignal(PULSE_ATTR):Connect(function()
			local _condition_1 = (folder:GetAttribute(PULSE_ATTR))
			if _condition_1 == nil then
				_condition_1 = 0
			end
			local current = _condition_1
			local _condition_2 = lastPulse[folder]
			if _condition_2 == nil then
				_condition_2 = 0
			end
			local prev = _condition_2
			lastPulse[folder] = current
			local delta = current - prev
			if delta > 0 then
				triggerRoom(folder, delta)
			end
		end)
	end
	RunService.RenderStepped:Connect(function(dt)
		-- ▼ ReadonlySet.size ▼
		local _size = 0
		for _ in activeRooms do
			_size += 1
		end
		-- ▲ ReadonlySet.size ▲
		if _size == 0 then
			return nil
		end
		for state in activeRooms do
			updateRoom(state, dt)
		end
	end)
end
return {
	init = init,
}
