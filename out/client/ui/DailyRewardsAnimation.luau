-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local TweenService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").TweenService
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
local playCashSound = TS.import(script, script.Parent.Parent, "audio", "CashSound").playCashSound
-- Opening sequence of the DailyRewards popup. Pure presentation — it only writes
-- what DailyRewardsBehavior already computed, and every value it touches is captured
-- on the first run and restored by stop(), so nothing authored in Studio is lost.
--
-- Sequence (fast on purpose — the popup must not feel like a cutscene):
--   1. every row cascades in from the top, staggered top → bottom      (~0.4s)
--   2. Base cash is already written, it never animates
--   3. the total counts up 0 → base × multiplier                       (0.5s)
--   4. LAST, after a longer beat, the day counter climbs from N−1 → N while the
--      label pops bigger, flashes and plays the cash sound, then settles back to
--      its authored size + colour                                      (0.45s)
--      N−1 means a first day (or a broken streak) visibly counts 0 → 1.
local ENTRANCE_OFFSET = 24
local ENTRANCE_TI = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ENTRANCE_STAGGER = 0.04
local TOTAL_COUNT_TI = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Breath between the total and the multiplier pop. Deliberately long: the day counter
-- is the payoff of the whole popup, it needs a beat of silence before it fires.
local MULT_GAP = 0.45
local MULT_COUNT_TI = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MULT_POP_TI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MULT_SETTLE_TI = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MULT_POP_SCALE = 1.35
local MULT_FLASH_COLOR = Color3.new(1, 0.84, 0.25)
-- alpha 1 = fully visible (authored value), alpha 0 = fully transparent.
-- A row's transparency is driven through one proxy per row rather than one tween per
-- property — a row is a label + its stroke + sometimes a button, and animating them
-- separately would multiply the tweens for no visual gain.
local function collectFades(root)
	local fades = {}
	local add = function(instance)
		if instance:IsA("UIStroke") then
			local authored = instance.Transparency
			table.insert(fades, function(alpha)
				instance.Transparency = 1 - (1 - authored) * alpha
			end)
			return nil
		end
		if instance:IsA("GuiObject") then
			local background = instance.BackgroundTransparency
			table.insert(fades, function(alpha)
				instance.BackgroundTransparency = 1 - (1 - background) * alpha
			end)
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			local text = instance.TextTransparency
			table.insert(fades, function(alpha)
				instance.TextTransparency = 1 - (1 - text) * alpha
			end)
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			local image = instance.ImageTransparency
			table.insert(fades, function(alpha)
				instance.ImageTransparency = 1 - (1 - image) * alpha
			end)
		end
	end
	add(root)
	for _, descendant in root:GetDescendants() do
		add(descendant)
	end
	return fades
end
-- Cascade order = the authored vertical layout, so re-arranging the popup in Studio
-- re-orders the animation on its own. Parent weight first (Header → Body → Buttons),
-- then the row's own Y scale inside that parent.
local function sortKey(row)
	local _result = row.Parent
	if _result ~= nil then
		_result = _result.Name
	end
	local _condition = _result
	if _condition == nil then
		_condition = ""
	end
	local parentName = _condition
	local weight = if parentName == "Body" then 1 elseif row.Name == "Header" then 0 else 2
	return weight + row.Position.Y.Scale
end
local generation = 0
local rows
local multiplierScale
local multiplierColor
local proxies = {}
-- One-shot capture of everything the sequence mutates. Done on the first play, when
-- the popup still holds exactly what Studio authored.
local function capture(refs)
	if rows then
		return rows
	end
	-- The multiplier pops through a UIScale so its authored Size/Position stay intact.
	-- Re-anchored to its centre (with a compensating Position) so it grows both ways
	-- instead of pushing down onto the title below — visually identical at rest.
	local label = refs.multiplierLabel
	if label.AnchorPoint.Y == 0 then
		label.AnchorPoint = Vector2.new(label.AnchorPoint.X, 0.5)
		local p = label.Position
		label.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale + label.Size.Y.Scale / 2, p.Y.Offset)
	end
	multiplierColor = label.TextColor3
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	multiplierScale = scale
	-- NB: the re-anchor above MUST happen before the rows record their positions —
	-- the cascade tweens each row back to what it captured here.
	local captured = {}
	local _exp = refs.rows
	-- ▼ ReadonlyArray.forEach ▼
	local _callback = function(instance)
		local _arg0 = {
			instance = instance,
			position = instance.Position,
			fades = collectFades(instance),
		}
		table.insert(captured, _arg0)
	end
	for _k, _v in _exp do
		_callback(_v, _k - 1, _exp)
	end
	-- ▲ ReadonlyArray.forEach ▲
	-- Stable sort: RobloxLua's table.sort isn't stable, so ties (the two buttons, same
	-- Y) are broken by their index in the authored list.
	local indexOf = {}
	-- ▼ ReadonlyArray.forEach ▼
	local _callback_1 = function(row, index)
		local _instance = row.instance
		local _index = index
		indexOf[_instance] = _index
		return indexOf
	end
	for _k, _v in captured do
		_callback_1(_v, _k - 1, captured)
	end
	-- ▲ ReadonlyArray.forEach ▲
	table.sort(captured, function(a, b)
		local ka = sortKey(a.instance)
		local kb = sortKey(b.instance)
		if ka ~= kb then
			return ka < kb
		end
		local _instance = a.instance
		local _condition = indexOf[_instance]
		if _condition == nil then
			_condition = 0
		end
		local _instance_1 = b.instance
		local _condition_1 = indexOf[_instance_1]
		if _condition_1 == nil then
			_condition_1 = 0
		end
		return _condition < _condition_1
	end)
	rows = captured
	return captured
end
local function applyFades(row, alpha)
	for _, fade in row.fades do
		fade(alpha)
	end
end
-- Tweens a number through a proxy NumberValue (same idiom as MoneyDisplay) and
-- renders each step through `format`.
local release
local function countTo(id, from, to, info, format)
	local proxy = Instance.new("NumberValue")
	proxy.Value = from
	table.insert(proxies, proxy)
	format(from)
	-- The generation guard matters on every step: a dropped sequence's tween keeps
	-- running on its (already released) proxy and must not write to the labels.
	proxy.Changed:Connect(function(value)
		if id == generation then
			format(value)
		end
	end)
	local tween = TweenService:Create(proxy, info, {
		Value = to,
	})
	tween.Completed:Connect(function()
		if id == generation then
			format(to)
		end
		release(proxy)
	end)
	tween:Play()
end
function release(proxy)
	local _proxy = proxy
	local index = (table.find(proxies, _proxy) or 0) - 1
	if index >= 0 then
		table.remove(proxies, index + 1)
	end
	proxy:Destroy()
end
local function clearProxies()
	local _array = {}
	local _length = #_array
	table.move(proxies, 1, #proxies, _length + 1, _array)
	for _, proxy in _array do
		proxy:Destroy()
	end
	while #proxies > 0 do
		proxies[#proxies] = nil
	end
end
local DailyRewardsAnimation = {
	play = function(self, refs, values)
		generation += 1
		local id = generation
		clearProxies()
		local captured = capture(refs)
		local total = math.floor(values.baseCash * values.multiplier)
		local renderTotal = function(value)
			refs.totalLabel.Text = `${FormatCash(math.floor(value))}`
		end
		local renderMultiplier = function(value)
			refs.multiplierLabel.Text = `{math.floor(value)}x`
		end
		-- 1. every row starts transparent, one notch above its resting position.
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(row)
			applyFades(row, 0)
			row.instance.Position = UDim2.new(row.position.X.Scale, row.position.X.Offset, row.position.Y.Scale, row.position.Y.Offset - ENTRANCE_OFFSET)
		end
		for _k, _v in captured do
			_callback(_v, _k - 1, captured)
		end
		-- ▲ ReadonlyArray.forEach ▲
		-- ▼ ReadonlyArray.forEach ▼
		local _callback_1 = function(row, index)
			task.delay(index * ENTRANCE_STAGGER, function()
				if id ~= generation or row.instance.Parent == nil then
					return nil
				end
				local proxy = Instance.new("NumberValue")
				table.insert(proxies, proxy)
				proxy.Changed:Connect(function(alpha)
					if id == generation then
						applyFades(row, alpha)
					end
				end)
				local fade = TweenService:Create(proxy, ENTRANCE_TI, {
					Value = 1,
				})
				fade.Completed:Connect(function()
					if id == generation then
						applyFades(row, 1)
					end
					release(proxy)
				end)
				fade:Play()
				TweenService:Create(row.instance, ENTRANCE_TI, {
					Position = row.position,
				}):Play()
			end)
		end
		for _k, _v in captured do
			_callback_1(_v, _k - 1, captured)
		end
		-- ▲ ReadonlyArray.forEach ▲
		local entranceEnd = (#captured - 1) * ENTRANCE_STAGGER + ENTRANCE_TI.Time
		-- Already claimed → no reveal, the numbers are just there.
		if not values.animateCounters then
			renderTotal(total)
			renderMultiplier(values.multiplier)
			return nil
		end
		-- 2. the total counts up from zero.
		-- The day counter starts one day BEHIND, so a first day — or a streak that was
		-- just lost — is seen climbing 0 → 1 rather than sitting on its final value.
		local multiplierFrom = math.max(0, values.multiplier - 1)
		renderTotal(0)
		renderMultiplier(multiplierFrom)
		task.delay(entranceEnd, function()
			if id ~= generation then
				return nil
			end
			countTo(id, 0, total, TOTAL_COUNT_TI, renderTotal)
		end)
		-- 3. LAST, the multiplier: pops bigger + flashes gold while it counts, then
		--    settles back to the authored size and colour.
		task.delay(entranceEnd + TOTAL_COUNT_TI.Time + MULT_GAP, function()
			if id ~= generation or not multiplierScale then
				return nil
			end
			refs.multiplierLabel.TextColor3 = MULT_FLASH_COLOR
			multiplierScale.Scale = 1
			playCashSound()
			TweenService:Create(multiplierScale, MULT_POP_TI, {
				Scale = MULT_POP_SCALE,
			}):Play()
			countTo(id, multiplierFrom, values.multiplier, MULT_COUNT_TI, renderMultiplier)
			task.delay(MULT_POP_TI.Time, function()
				if id ~= generation or not multiplierScale then
					return nil
				end
				TweenService:Create(multiplierScale, MULT_SETTLE_TI, {
					Scale = 1,
				}):Play()
				if multiplierColor ~= nil then
					TweenService:Create(refs.multiplierLabel, MULT_SETTLE_TI, {
						TextColor3 = multiplierColor,
					}):Play()
				end
			end)
		end)
	end,
	stop = function(self, refs, values)
		generation += 1
		clearProxies()
		if rows then
			for _, row in rows do
				applyFades(row, 1)
				row.instance.Position = row.position
			end
		end
		if multiplierScale then
			multiplierScale.Scale = 1
		end
		if multiplierColor ~= nil then
			refs.multiplierLabel.TextColor3 = multiplierColor
		end
		refs.totalLabel.Text = `${FormatCash(math.floor(values.baseCash * values.multiplier))}`
		refs.multiplierLabel.Text = `{values.multiplier}x`
	end,
}
return {
	DailyRewardsAnimation = DailyRewardsAnimation,
}
