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
local FlyTI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Pause à taille native avant que le label ne s'envole (pas de bump au spawn).
local HOLD_BEFORE_FLY = 0.17
-- ── Internal ──────────────────────────────────────────────────────────────────
-- Clone le template Studio (visuels et taille inchangés) et met à jour le texte.
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
	frame.Parent = parent
	return frame
end
-- ── Public API ────────────────────────────────────────────────────────────────
-- Fait apparaître un clone du template à une position aléatoire centrale (à sa
-- taille Studio, sans ajustement), marque une courte pause, puis le fait voler
-- vers targetLabel. onArrived est appelé à l'impact pour bumper le MultiplierLabel.
local function spawnFloatingMultiplierLabel(parent, template, delta, targetLabel, onArrived)
	local spawnX = SPAWN.xMin + math.random() * (SPAWN.xMax - SPAWN.xMin)
	local spawnY = SPAWN.yMin + math.random() * (SPAWN.yMax - SPAWN.yMin)
	local frame = build(template, parent, delta)
	frame.Position = UDim2.new(spawnX, 0, spawnY, 0)
	task.delay(HOLD_BEFORE_FLY, function()
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
end
return {
	spawnFloatingMultiplierLabel = spawnFloatingMultiplierLabel,
}
