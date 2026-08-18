-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local RunService = _services.RunService
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
local FRAME_NAME = "MoneyBurstBill"
-- ── Simulation ──────────────────────────────────────────────────────────────────
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
local function destroyBill(index)
	bills[index + 1].label:Destroy()
	local _index = index
	table.remove(bills, _index + 1)
end
local function step(dt)
	-- dt borné : un freeze (chargement, alt-tab) ne doit pas téléporter les billets.
	local delta = math.min(dt, 1 / 20)
	for i = #bills - 1, 0, -1 do
		local bill = bills[i + 1]
		bill.age += delta
		-- Freinage exponentiel + gravité : gerbe rapide au départ, chute posée ensuite.
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
		local label = bill.label
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
		local _result = stepConn
		if _result ~= nil then
			_result:Disconnect()
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
	play = function(self, origin)
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
			local _arg0 = {
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
			table.insert(bills, _arg0)
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
