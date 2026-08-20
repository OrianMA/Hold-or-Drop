-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local RunService = _services.RunService
local playBillPop = TS.import(script, script.Parent.Parent, "audio", "CashSound").playBillPop
-- ── Explosion de billets 2D (particules = ImageLabels) ──────────────────────────
--
-- Jouée au claim : une gerbe d'images part du centre, se disperse d'un coup dans
-- toutes les directions, freine (drag), puis retombe doucement en tournoyant avant
-- de s'effacer. Purement client, purement visuel — aucune interaction, aucun réseau.
--
-- Pas de ParticleEmitter ici : c'est de la 2D écran (les billets doivent rester
-- lisibles par-dessus le HUD), donc une mini simulation en pixels dans RenderStepped.
local MONEY_IMAGE = "rbxassetid://18209585783"
-- ── Tuning ──────────────────────────────────────────────────────────────────────
-- Toutes les valeurs en pixels sont exprimées pour un écran de REFERENCE_HEIGHT px
-- et remises à l'échelle du viewport réel (mobile compris).
local REFERENCE_HEIGHT = 900
local PARTICLE_COUNT = 26
local BILL_SIZE = 70
local BILL_SIZE_JITTER = 0.35
local SPEED_MIN = 700
local SPEED_MAX = 1500
local DRAG = 2.6
local GRAVITY = 1500
local SPIN_MAX = 320
local SWAY_AMPLITUDE = 90
local SWAY_SPEED_MIN = 2
local SWAY_SPEED_MAX = 5
local POP_TIME = 0.1
local LIFETIME = 2.6
local FADE_START = 1.5
-- ── Variante "aspiration" (récompense journalière) ──────────────────────────────
-- Même explosion, mais au lieu de retomber et de s'effacer, les billets sont aspirés
-- vers une cible (le compteur d'argent du HUD). Le vol est accéléré (p²) : ils
-- décollent mollement puis filent dans le compteur, ce qui lit comme une aspiration
-- plutôt qu'un déplacement linéaire.
local GATHER_TIME = 0.75
-- Les billets ne basculent PAS tous en même temps : le départ de l'aspiration est
-- échelonné sur GATHER_SPREAD dans l'ordre d'émission (donc en vague autour du
-- cercle), plus un petit bruit pour que ça ne soit pas mécanique.
local GATHER_SPREAD = 0.25
local GATHER_JITTER = 0.05
-- Temps de FREINAGE entre la fin de l'explosion et le départ vers la cible. Le billet
-- n'est pas gelé d'un coup : sa vitesse (translation ET rotation) est multipliée par
-- une courbe qui vaut 1 à l'entrée et 0 à la sortie, dérivée nulle aux deux bouts. Il
-- finit donc immobile — la pause est bien là — mais en y arrivant en glissant.
local GATHER_BRAKE = 0.2
-- Orientation prise pendant le vol : le billet cesse de tournoyer et se remet droit.
local GATHER_END_ROTATION = 0
local GATHER_END_SCALE = 0.25
local GATHER_FADE_FROM = 0.8
local FRAME_NAME = "MoneyBurstBill"
-- ── Simulation ──────────────────────────────────────────────────────────────────
-- s de lévitation (explosion libre) avant que l'aspiration ne commence.
local GATHER_DELAY = 0.55
local bills = {}
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
-- Interpolation douce (3t²−2t³) : dérivée nulle aux deux bouts, donc aucune cassure
-- visible quand un régime prend le relais de l'autre.
local function smoothstep(t)
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end
-- Écart d'angle le plus court (−180..180) : le billet retrouve son orientation de
-- départ par le chemin le plus court, jamais en refaisant un tour complet.
local function shortestAngle(from, to)
	return (((to - from + 180) % 360) + 360) % 360 - 180
end
local function destroyBill(index)
	bills[index + 1].label:Destroy()
	local _index = index
	table.remove(bills, _index + 1)
end
local function step(dt)
	-- dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les billets.
	local delta = math.min(dt, 1 / 20)
	-- Origine du ScreenGui : les billets sont positionnés en offsets LOCAUX, alors que
	-- la cible d'aspiration est donnée en coordonnées écran absolues.
	local _result = getScreenGui()
	if _result ~= nil then
		_result = _result.AbsolutePosition
	end
	local _condition = _result
	if _condition == nil then
		_condition = Vector2.new(0, 0)
	end
	local origin = _condition
	for i = #bills - 1, 0, -1 do
		local bill = bills[i + 1]
		bill.age += delta
		local label = bill.label
		-- ── Aspiration : arrêt net, puis ligne droite vers la cible ───────────────
		if bill.gatherAt ~= nil and bill.age >= bill.gatherAt then
			if not bill.gathering then
				local _target = bill.resolveTarget
				if _target ~= nil then
					_target = _target()
				end
				local target = _target
				if not target then
					-- Pas de cible (HUD absent) → on repasse en fondu normal plutôt que
					-- de laisser le billet figé en l'air.
					bill.gatherAt = nil
				else
					-- Point d'entrée du freinage. fromX/fromY/rotationFrom sont réécrits à
					-- chaque image tant que le billet glisse encore, pour que la ligne
					-- droite parte de son point d'arrêt RÉEL.
					bill.gathering = {
						fromX = bill.x,
						fromY = bill.y,
						toX = target.X - origin.X,
						toY = target.Y - origin.Y,
						rotationFrom = bill.rotation,
						elapsed = 0,
					}
				end
			end
			local gathering = bill.gathering
			if gathering then
				gathering.elapsed += delta
				-- 1. Freinage : le billet continue sur sa lancée en ralentissant jusqu'à
				--    l'arrêt. La vitesse est CONTINUE de part et d'autre — à l'entrée elle
				--    vaut encore celle de l'explosion, à la sortie exactement zéro — donc
				--    aucune cassure visible. La gravité ne s'applique plus ici, sinon le
				--    billet ne s'immobiliserait jamais.
				if gathering.elapsed < GATHER_BRAKE then
					local brake = 1 - smoothstep(gathering.elapsed / GATHER_BRAKE)
					bill.x += bill.vx * brake * delta
					bill.y += bill.vy * brake * delta
					bill.rotation += bill.spin * brake * delta
					gathering.fromX = bill.x
					gathering.fromY = bill.y
					gathering.rotationFrom = bill.rotation
					label.Position = UDim2.new(0, bill.x, 0, bill.y)
					label.Rotation = bill.rotation
					continue
				end
				-- 2. Vol en ligne droite, easing p². Sa dérivée est nulle en p = 0 : le
				--    départ se fait donc à vitesse nulle, dans la continuité exacte du
				--    freinage — puis ça accélère jusqu'à l'arrivée.
				local p = math.clamp((gathering.elapsed - GATHER_BRAKE) / GATHER_TIME, 0, 1)
				local eased = p * p
				local drawX = gathering.fromX + (gathering.toX - gathering.fromX) * eased
				local drawY = gathering.fromY + (gathering.toY - gathering.fromY) * eased
				-- Le billet se remet droit pendant le vol, par le chemin angulaire le
				-- plus court : il arrive à plat dans le compteur, sans tournoyer.
				local settle = smoothstep(p)
				local rotation = gathering.rotationFrom + shortestAngle(gathering.rotationFrom, GATHER_END_ROTATION) * settle
				local drawn = bill.size * (1 - (1 - GATHER_END_SCALE) * eased)
				label.Position = UDim2.new(0, drawX, 0, drawY)
				label.Size = UDim2.new(0, drawn, 0, drawn)
				label.Rotation = rotation
				label.ImageTransparency = if p > GATHER_FADE_FROM then (p - GATHER_FADE_FROM) / (1 - GATHER_FADE_FROM) else 0
				if p >= 1 then
					playBillPop()
					destroyBill(i)
				end
				continue
			end
		end
		-- ── Explosion : freinage exponentiel + gravité ────────────────────────────
		-- Gerbe rapide au départ, chute posée ensuite.
		local damping = math.exp(-DRAG * delta)
		bill.vx *= damping
		bill.vy = bill.vy * damping + GRAVITY * bill.scale * delta
		-- Balancement latéral façon feuille de papier, seulement une fois le jet freiné.
		bill.swayPhase += bill.swaySpeed * delta
		bill.vx += math.sin(bill.swayPhase) * SWAY_AMPLITUDE * bill.scale * delta
		bill.x += bill.vx * delta
		bill.y += bill.vy * delta
		bill.spin *= damping
		bill.rotation += bill.spin * delta
		local grow = if bill.age < POP_TIME then bill.age / POP_TIME else 1
		local drawn = bill.size * grow
		label.Position = UDim2.new(0, bill.x, 0, bill.y)
		label.Size = UDim2.new(0, drawn, 0, drawn)
		label.Rotation = bill.rotation
		if bill.age > FADE_START then
			label.ImageTransparency = math.clamp((bill.age - FADE_START) / (LIFETIME - FADE_START), 0, 1)
		end
		if bill.age >= LIFETIME then
			destroyBill(i)
		end
	end
	if #bills == 0 then
		local _result_1 = stepConn
		if _result_1 ~= nil then
			_result_1:Disconnect()
		end
		stepConn = nil
	end
end
-- ── API ─────────────────────────────────────────────────────────────────────────
local MoneyBurst = {
	preload = function(self)
		task.spawn(function()
			local probe = Instance.new("ImageLabel")
			probe.Image = MONEY_IMAGE
			pcall(function()
				return ContentProvider:PreloadAsync({ probe })
			end)
			probe:Destroy()
		end)
	end,
	play = function(self, origin, options)
		local screenGui = getScreenGui()
		if not screenGui then
			return nil
		end
		local viewport = screenGui.AbsoluteSize
		if viewport.X == 0 or viewport.Y == 0 then
			return nil
		end
		local scale = viewport.Y / REFERENCE_HEIGHT
		local center = origin or viewport / 2
		for i = 0, PARTICLE_COUNT - 1 do
			-- Angles répartis sur le cercle complet + bruit : dispersion "d'un coup"
			-- dans toutes les directions, sans trou visible dans la gerbe.
			local angle = ((i + math.random()) / PARTICLE_COUNT) * math.pi * 2
			local speed = (SPEED_MIN + math.random() * (SPEED_MAX - SPEED_MIN)) * scale
			local sizeJitter = 1 + (math.random() * 2 - 1) * BILL_SIZE_JITTER
			local label = Instance.new("ImageLabel")
			label.Name = FRAME_NAME
			label.Image = MONEY_IMAGE
			label.BackgroundTransparency = 1
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.new(0, center.X, 0, center.Y)
			label.Size = UDim2.new(0, 0, 0, 0)
			label.ZIndex = 50
			label.Active = false
			label.Parent = screenGui
			local _object = {
				label = label,
				x = center.X,
				y = center.Y,
				vx = math.cos(angle) * speed,
				vy = math.sin(angle) * speed,
				size = BILL_SIZE * sizeJitter * scale,
				scale = scale,
				rotation = math.random() * 360,
				spin = (math.random() * 2 - 1) * SPIN_MAX,
				swayPhase = math.random() * math.pi * 2,
				swaySpeed = SWAY_SPEED_MIN + math.random() * (SWAY_SPEED_MAX - SWAY_SPEED_MIN),
				age = 0,
			}
			local _left = "gatherAt"
			local _result
			if options then
				local _condition = options.gatherAfter
				if _condition == nil then
					_condition = GATHER_DELAY
				end
				_result = _condition + (i / PARTICLE_COUNT) * GATHER_SPREAD + math.random() * GATHER_JITTER
			else
				_result = nil
			end
			_object[_left] = _result
			local _left_1 = "resolveTarget"
			local _result_1 = options
			if _result_1 ~= nil then
				_result_1 = _result_1.gatherTo
			end
			_object[_left_1] = _result_1
			table.insert(bills, _object)
		end
		if not stepConn then
			stepConn = RunService.RenderStepped:Connect(step)
		end
	end,
	clear = function(self)
		for _, bill in bills do
			bill.label:Destroy()
		end
		table.clear(bills)
		local _result = stepConn
		if _result ~= nil then
			_result:Disconnect()
		end
		stepConn = nil
	end,
}
return {
	MoneyBurst = MoneyBurst,
}
