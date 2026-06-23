-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Cfg = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "LeaderboardConfig")
-- Drives the 3 podium rigs. Avatar (ApplyDescription) only reloads when a slot's
-- occupant changes — the costly call, gated on change. ApplyDescription rescales
-- the rig to the player's avatar, so the rig is re-seated feet-on-pedestal after
-- every swap (target captured from the template at build time). Slot 1 walks,
-- 2 & 3 idle. Empty slots are hidden by parenting the rig out (it keeps its parts
-- and reappears on the same spot when shown again).
local slots
local function buildSlots(podium)
	local built = {}
	for i = 1, 3 do
		local rig = podium:FindFirstChild(`{Cfg.PODIUM_RIG_PREFIX}{i}`)
		if not rig then
			return nil
		end
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return nil
		end
		local bbCF, bbSize = rig:GetBoundingBox()
		local _arg0 = {
			rig = rig,
			home = podium,
			humanoid = humanoid,
			animator = humanoid:FindFirstChildOfClass("Animator"),
			animId = if i == 1 then Cfg.WALK_ANIM_ID else Cfg.IDLE_ANIM_ID,
			standX = bbCF.Position.X,
			standZ = bbCF.Position.Z,
			standTopY = bbCF.Position.Y - bbSize.Y / 2,
			hidden = false,
		}
		table.insert(built, _arg0)
	end
	return built
end
-- Re-seat the rig so its feet rest on the pedestal, centred on the stand point,
-- facing -Z. Reads the live bounding box so it is robust to the rescale that
-- ApplyDescription performs (and to the template's custom pivot).
local function placeOnPedestal(slot)
	local bbCF, bbSize = slot.rig:GetBoundingBox()
	local pivot = slot.rig:GetPivot()
	local _position = pivot.Position
	local _position_1 = bbCF.Position
	local pivotToCenter = _position - _position_1
	local targetCenter = Vector3.new(slot.standX, slot.standTopY + bbSize.Y / 2, slot.standZ)
	slot.rig:PivotTo(CFrame.new(targetCenter + pivotToCenter))
end
local function ensureAnimation(slot)
	local animator = slot.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if slot.animator ~= animator then
		slot.animator = animator
		slot.track = nil
	end
	if not slot.track then
		local anim = Instance.new("Animation")
		anim.AnimationId = slot.animId
		slot.track = animator:LoadAnimation(anim)
		slot.track.Looped = true
	end
	if not slot.track.IsPlaying then
		slot.track:Play()
	end
end
local function getNameplate(slot)
	local head = slot.rig:FindFirstChild("Head")
	if not head then
		return nil
	end
	local plate = head:FindFirstChild(Cfg.PODIUM_NAMEPLATE)
	if not plate then
		plate = Instance.new("BillboardGui")
		plate.Name = Cfg.PODIUM_NAMEPLATE
		plate.Size = UDim2.new(0, 200, 0, 64)
		plate.StudsOffset = Vector3.new(0, 2.5, 0)
		plate.AlwaysOnTop = true
		plate.Adornee = head
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = Cfg.ROW_NAME
		nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Parent = plate
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = Cfg.ROW_VALUE
		valueLabel.Position = UDim2.new(0, 0, 0.5, 0)
		valueLabel.Size = UDim2.new(1, 0, 0.5, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.TextScaled = true
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		valueLabel.Parent = plate
		plate.Parent = head
	end
	return {
		name = plate:FindFirstChild(Cfg.ROW_NAME),
		value = plate:FindFirstChild(Cfg.ROW_VALUE),
	}
end
local function show(slot)
	if slot.hidden then
		slot.rig.Parent = slot.home
		slot.hidden = false
	end
end
local function hide(slot)
	if not slot.hidden then
		slot.rig.Parent = nil
		slot.hidden = true
	end
	slot.occupant = nil
end
local function applyAvatar(slot, userId)
	-- On a transient fetch/apply failure we DON'T record the occupant, so the next
	-- refresh retries instead of leaving the rig stuck on the template appearance.
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not ok then
		return nil
	end
	local applied = pcall(function()
		return slot.humanoid:ApplyDescription(desc)
	end)
	if not applied then
		return nil
	end
	-- ApplyDescription rebuilds + rescales the body — re-anchor the root and
	-- re-seat the (now correctly sized) rig on the pedestal.
	local root = slot.rig:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
	placeOnPedestal(slot)
	slot.occupant = userId
end
local function renderPodium(podium, top3, format)
	if not slots then
		slots = buildSlots(podium)
	end
	if not slots then
		return nil
	end
	for i = 0, 2 do
		local slot = slots[i + 1]
		local entry = top3[i + 1]
		if not entry then
			hide(slot)
			continue
		end
		show(slot)
		if slot.occupant ~= entry.userId then
			applyAvatar(slot, entry.userId)
		end
		local plate = getNameplate(slot)
		if plate then
			plate.name.Text = entry.name
			plate.value.Text = format(entry.value)
		end
		ensureAnimation(slot)
	end
end
return {
	renderPodium = renderPodium,
}
