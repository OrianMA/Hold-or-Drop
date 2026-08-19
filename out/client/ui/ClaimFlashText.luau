-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
local _RocketGameConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "RocketGameConfig")
local CRITICAL_CLAIM_MULTIPLIER = _RocketGameConfig.CRITICAL_CLAIM_MULTIPLIER
local PERFECT_CLAIM_MULTIPLIER = _RocketGameConfig.PERFECT_CLAIM_MULTIPLIER
-- ── Flashs de claim bonus ──────────────────────────────────────────────────────
--
-- Deux textes plein écran, même animation et même son :
--   • "PERFECT CLAIM  BASE CASH ×3"  — rouge  — claim juste avant l'explosion, joué À
--     L'EXPLOSION (c'est le boom qui valide le coup).
--   • "CRITICAL CLAIM  BASE CASH ×10" — doré et brillant (dégradé balayé par un reflet)
--     — 5 % de chance à chaque claim, joué AU CLAIM.
--
-- Les deux bonus multiplient le BASE CASH, jamais le multiplicateur : le texte le dit
-- explicitement, et la popup de fin montre la base grimper (client/ui/EndGameAnimation).
--
-- Les deux peuvent tomber sur le même run : comme les bandeaux InformationText, chaque
-- flash prend sa propre ligne (slot) et vit sa vie indépendamment — plusieurs textes
-- peuvent donc être affichés en même temps, jamais l'un sur l'autre.
--
-- Rien à préparer en Studio : les labels sont créés en code sous InGameUI, donc ils
-- suivent automatiquement le viewport (TextScaled + tailles en scale ⇒ lisible mobile).
local LABEL_NAME = "ClaimFlashText"
local SIZE = UDim2.fromScale(0.72, 0.13)
local BASE_Y = 0.43
local SLOT_SPACING = 0.15
local MAX_FLASHES = 3
local Z_INDEX = 60
local STROKE_THICKNESS = 4
-- Arrivée : le texte débarque énorme et de travers, puis claque à sa taille.
local START_SCALE = 2.4
local START_ROTATION = -7
local SLAM_TI = TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local APPEAR_TI = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD = 2
local OUT_SCALE = 1.3
local OUT_TI = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Reflet du critical : le dégradé doré est balayé de gauche à droite en boucle. Hors du
-- balayage le texte reste doré (les deux bouts du dégradé sont de l'or foncé).
local SHINE_TI = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)
local GOLD_GRADIENT = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 32)), ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 214, 92)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 235)), ColorSequenceKeypoint.new(0.58, Color3.fromRGB(255, 214, 92)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 32)) })
local SHINE_ROTATION = 20
local PERFECT_STYLE = {
	text = `PERFECT CLAIM  BASE CASH ×{PERFECT_CLAIM_MULTIPLIER}`,
	color = Color3.fromRGB(255, 38, 38),
	shine = false,
}
local CRITICAL_STYLE = {
	text = `CRITICAL CLAIM  BASE CASH ×{CRITICAL_CLAIM_MULTIPLIER}`,
	color = Color3.new(1, 1, 1),
	shine = true,
}
-- ── Son ───────────────────────────────────────────────────────────────────────
-- Template persistant en SoundService (même approche que UiClickSound / InformationText) :
-- l'asset reste en mémoire, les clones peuvent se chevaucher.
local soundTemplate
local function playSound()
	if not soundTemplate then
		local template = Instance.new("Sound")
		template.Name = "ClaimFlashSoundTemplate"
		template.SoundId = AudioConfig.sfx.perfectClaim.id
		template.Volume = AudioConfig.sfx.perfectClaim.volume
		template.Parent = SoundService
		soundTemplate = template
	end
	local sound = soundTemplate:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		return sound:Destroy()
	end)
end
-- ── Pile active ───────────────────────────────────────────────────────────────
local active = {}
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
-- Plus petite ligne libre : deux flashs simultanés ne se superposent jamais.
local function freeSlot()
	for slot = 0, MAX_FLASHES - 1 do
		local taken = false
		for _, flash in active do
			if flash.slot == slot then
				taken = true
			end
		end
		if not taken then
			return slot
		end
	end
	return 0
end
local function remove(flash)
	if not flash.alive then
		return nil
	end
	flash.alive = false
	for _, tween in flash.tweens do
		tween:Cancel()
	end
	table.clear(flash.tweens)
	flash.label:Destroy()
	local _flash = flash
	local index = (table.find(active, _flash) or 0) - 1
	if index >= 0 then
		table.remove(active, index + 1)
	end
end
local function play(flash, target, info, goal)
	local tween = TweenService:Create(target, info, goal)
	local _exp = flash.tweens
	table.insert(_exp, tween)
	tween:Play()
end
local function show(style)
	local screenGui = getScreenGui()
	if not screenGui then
		return nil
	end
	if #active >= MAX_FLASHES then
		remove(active[1])
	end
	local slot = freeSlot()
	local label = Instance.new("TextLabel")
	label.Name = LABEL_NAME
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, BASE_Y + slot * SLOT_SPACING)
	label.Size = SIZE
	label.BackgroundTransparency = 1
	label.Text = style.text
	label.TextScaled = true
	label.TextColor3 = style.color
	label.TextTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.ZIndex = Z_INDEX
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = START_SCALE
	scale.Parent = label
	label.Rotation = START_ROTATION
	label.Parent = screenGui
	local flash = {
		label = label,
		stroke = stroke,
		scale = scale,
		tweens = {},
		slot = slot,
		alive = true,
	}
	table.insert(active, flash)
	-- Critical : dégradé doré + reflet qui traverse le texte en boucle.
	if style.shine then
		local gradient = Instance.new("UIGradient")
		gradient.Color = GOLD_GRADIENT
		gradient.Rotation = SHINE_ROTATION
		gradient.Offset = Vector2.new(-1, 0)
		gradient.Parent = label
		play(flash, gradient, SHINE_TI, {
			Offset = Vector2.new(1, 0),
		})
	end
	playSound()
	play(flash, scale, SLAM_TI, {
		Scale = 1,
	})
	play(flash, label, SLAM_TI, {
		Rotation = 0,
	})
	play(flash, label, APPEAR_TI, {
		TextTransparency = 0,
	})
	play(flash, stroke, APPEAR_TI, {
		Transparency = 0,
	})
	task.delay(SLAM_TI.Time + HOLD, function()
		if not flash.alive then
			return nil
		end
		play(flash, scale, OUT_TI, {
			Scale = OUT_SCALE,
		})
		play(flash, label, OUT_TI, {
			TextTransparency = 1,
		})
		play(flash, stroke, OUT_TI, {
			Transparency = 1,
		})
		task.delay(OUT_TI.Time, function()
			return remove(flash)
		end)
	end)
end
local ClaimFlashText = {
	showPerfect = function(self)
		show(PERFECT_STYLE)
	end,
	showCritical = function(self)
		show(CRITICAL_STYLE)
	end,
	hide = function(self)
		for i = #active - 1, 0, -1 do
			remove(active[i + 1])
		end
	end,
}
return {
	ClaimFlashText = ClaimFlashText,
}
