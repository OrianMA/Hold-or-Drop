-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local TweenService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").TweenService
-- ── Configuration ─────────────────────────────────────────────────────────────
-- Zone d'apparition aléatoire (coordonnées écran, scale 0–1)
local SPAWN = {
	xMin = 0.4,
	xMax = 0.6,
	yMin = 0.25,
	yMax = 0.4,
}
local BumpInTI = TweenInfo.new(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BumpOutTI = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FlyTI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- ── Internal ──────────────────────────────────────────────────────────────────
-- Clone le template Studio (visuels inchangés), met à jour le texte,
-- et ajoute uniquement le UIScale nécessaire pour l'animation bump.
local function build(template, parent, delta)
	local frame = template:Clone()
	frame.Name = "FloatingMultiplierLabel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 20
	frame.Visible = true
	local amountLabel = frame:FindFirstChild("Amount")
	if amountLabel then
		amountLabel.Text = `+{tostring(math.round(delta * 10) / 10)}`
	end
	-- UIScale sur l'icône uniquement — la frame et le texte gardent leur taille Studio
	local icon = frame:FindFirstChild("Icon")
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.9
	uiScale.Parent = icon or frame
	frame.Parent = parent
	return { frame, uiScale }
end
-- ── Public API ────────────────────────────────────────────────────────────────
-- Fait apparaître un clone du template à une position aléatoire centrale,
-- le fait bumper (0.9 → 1.1 → 1.0), puis voler vers targetLabel.
-- onArrived est appelé à l'impact pour déclencher le bump du MultiplierLabel.
local function spawnFloatingMultiplierLabel(parent, template, delta, targetLabel, onArrived)
	local spawnX = SPAWN.xMin + math.random() * (SPAWN.xMax - SPAWN.xMin)
	local spawnY = SPAWN.yMin + math.random() * (SPAWN.yMax - SPAWN.yMin)
	local _binding = build(template, parent, delta)
	local frame = _binding[1]
	local uiScale = _binding[2]
	frame.Position = UDim2.new(spawnX, 0, spawnY, 0)
	-- Bump in : 0.9 → 1.1
	TweenService:Create(uiScale, BumpInTI, {
		Scale = 1.1,
	}):Play()
	task.delay(BumpInTI.Time, function()
		-- Settle : 1.1 → 1.0
		TweenService:Create(uiScale, BumpOutTI, {
			Scale = 1.0,
		}):Play()
		task.delay(BumpOutTI.Time + 0.04, function()
			local screenSize = parent.AbsoluteSize
			if screenSize.X == 0 then
				frame:Destroy()
				onArrived()
				return nil
			end
			-- Centre absolu du targetLabel → coordonnées écran (scale)
			local _absolutePosition = targetLabel.AbsolutePosition
			local _arg0 = targetLabel.AbsoluteSize / 2
			local targetCenter = _absolutePosition + _arg0
			local targetPos = UDim2.new(targetCenter.X / screenSize.X, 0, targetCenter.Y / screenSize.Y, 0)
			local flyTween = TweenService:Create(frame, FlyTI, {
				Position = targetPos,
			})
			flyTween.Completed:Connect(function()
				frame:Destroy()
				onArrived()
			end)
			flyTween:Play()
		end)
	end)
end
return {
	spawnFloatingMultiplierLabel = spawnFloatingMultiplierLabel,
}
