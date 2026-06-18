-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local CollectionService = _services.CollectionService
local RunService = _services.RunService
local MusicController = TS.import(script, script.Parent.Parent, "audio", "MusicController").MusicController
-- Visualiser de spectre du lobby : des barres d'égaliseur rendues sur chaque part
-- taguée VISUALIZER_TAG. Le spectre de la BGM est lu UNE fois par tick puis appliqué
-- à tous les panneaux. 100 % client, présentation uniquement.
local VISUALIZER_TAG = "AudioVisualizer"
-- --- réglages -------------------------------------------------------------
local BAR_COUNT = 32
local UPDATE_HZ = 30
local RELEASE_PER_SEC = 2.2
local SPECTRUM_SCALE = 12
local COMPRESS_EXP = 0.5
local MIN_BAR_SCALE = 0.02
local FREQ_MIN = 20
local FREQ_MAX = 6000
local SAMPLE_RATE_HALF = 24000
local BAR_GAP_SCALE = 0.3
local COLOR_LEFT = Color3.fromRGB(86, 224, 255)
local COLOR_RIGHT = Color3.fromRGB(157, 107, 255)
-- Un panneau rendu (les barres vivent dans une SurfaceGui sur une part taguée).
local panels = {}
-- Buffers réutilisés entre les ticks (aucune allocation par tick côté nous).
local smoothed = {}
local bandBuf = {}
for i = 0, BAR_COUNT - 1 do
	smoothed[i + 1] = 0
	bandBuf[i + 1] = 0
end
local SLOT = 1 / BAR_COUNT
local BAR_WIDTH = SLOT * (1 - BAR_GAP_SCALE)
local function buildPanel(part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AudioVisualizer"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = part
	local bars = {}
	for i = 0, BAR_COUNT - 1 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.fromScale((i + 0.5) * SLOT, 1)
		bar.Size = UDim2.fromScale(BAR_WIDTH, MIN_BAR_SCALE)
		bar.BackgroundColor3 = COLOR_LEFT:Lerp(COLOR_RIGHT, i / (BAR_COUNT - 1))
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.4, 0)
		corner.Parent = bar
		bar.Parent = gui
		bars[i + 1] = bar
	end
	return {
		gui = gui,
		bars = bars,
	}
end
local function removePanel(part)
	local _part = part
	local panel = panels[_part]
	if not panel then
		return nil
	end
	panel.gui:Destroy()
	local _part_1 = part
	panels[_part_1] = nil
end
local function addPart(inst)
	local _condition = inst:IsA("BasePart")
	if _condition then
		local _inst = inst
		_condition = not (panels[_inst] ~= nil)
	end
	if _condition then
		local _inst = inst
		local _arg1 = buildPanel(inst)
		panels[_inst] = _arg1
	end
end
-- Mappe le spectre linéaire 0..24 kHz en BAR_COUNT bandes log-espacées dans [0,1].
-- Indexation 0-based (roblox-ts) : les bins valides vont de 0 à bins-1.
local function readBands(target)
	local analyzer = MusicController:getBgmAnalyzer()
	local spectrum = if analyzer ~= nil then analyzer:GetSpectrum() else nil
	if spectrum == nil or #spectrum == 0 then
		for i = 0, BAR_COUNT - 1 do
			target[i + 1] = 0
		end
		return nil
	end
	local bins = #spectrum
	local ratio = FREQ_MAX / FREQ_MIN
	for i = 0, BAR_COUNT - 1 do
		local fLo = FREQ_MIN * math.pow(ratio, i / BAR_COUNT)
		local fHi = FREQ_MIN * math.pow(ratio, (i + 1) / BAR_COUNT)
		local lo = math.floor((fLo / SAMPLE_RATE_HALF) * bins)
		local hi = math.floor((fHi / SAMPLE_RATE_HALF) * bins)
		if lo < 0 then
			lo = 0
		end
		if hi > bins then
			hi = bins
		end
		if hi <= lo then
			hi = math.min(lo + 1, bins)
		end
		local sum = 0
		do
			local b = lo
			local _shouldIncrement = false
			while true do
				if _shouldIncrement then
					b += 1
				else
					_shouldIncrement = true
				end
				if not (b < hi) then
					break
				end
				sum += spectrum[b + 1]
			end
		end
		local level = sum / (hi - lo)
		target[i + 1] = math.clamp(math.pow(level * SPECTRUM_SCALE, COMPRESS_EXP), 0, 1)
	end
end
local function step(dt)
	readBands(bandBuf)
	for i = 0, BAR_COUNT - 1 do
		local t = bandBuf[i + 1]
		local prev = smoothed[i + 1]
		-- attaque instantanée, chute lente
		smoothed[i + 1] = if t >= prev then t else math.max(t, prev - RELEASE_PER_SEC * dt)
	end
	for _, panel in panels do
		for i = 0, BAR_COUNT - 1 do
			local h = MIN_BAR_SCALE + (1 - MIN_BAR_SCALE) * smoothed[i + 1]
			panel.bars[i + 1].Size = UDim2.fromScale(BAR_WIDTH, h)
		end
	end
end
local UPDATE_INTERVAL = 1 / UPDATE_HZ
local accumulator = 0
local function init()
	for _, inst in CollectionService:GetTagged(VISUALIZER_TAG) do
		addPart(inst)
	end
	CollectionService:GetInstanceAddedSignal(VISUALIZER_TAG):Connect(function(inst)
		return addPart(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(VISUALIZER_TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			removePanel(inst)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		-- ▼ ReadonlyMap.size ▼
		local _size = 0
		for _ in panels do
			_size += 1
		end
		-- ▲ ReadonlyMap.size ▲
		if _size == 0 then
			return nil
		end
		accumulator += dt
		if accumulator < UPDATE_INTERVAL then
			return nil
		end
		step(accumulator)
		accumulator = 0
	end)
end
return {
	init = init,
}
