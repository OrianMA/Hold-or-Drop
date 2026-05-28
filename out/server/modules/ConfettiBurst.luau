-- Compiled with roblox-ts v3.0.0
-- Enables the Confetti ParticleEmitters under a button model for 2s then
-- disables them. The Confetti folder may contain either ParticleEmitters
-- directly or Attachments holding them — both are handled.
local DEFAULT_DURATION = 2
local function collectEmitters(confettiContainer)
	local emitters = {}
	for _, child in confettiContainer:GetDescendants() do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
		end
	end
	return emitters
end
local ConfettiBurst = {
	play = function(self, buttonModel, duration)
		if duration == nil then
			duration = DEFAULT_DURATION
		end
		if not buttonModel then
			return nil
		end
		local container = buttonModel:FindFirstChild("Confetti")
		if not container then
			return nil
		end
		local emitters = collectEmitters(container)
		if #emitters == 0 then
			return nil
		end
		for _, emitter in emitters do
			emitter.Enabled = true
		end
		task.delay(duration, function()
			for _, emitter in emitters do
				if emitter.Parent == nil then
					continue
				end
				emitter.Enabled = false
			end
		end)
	end,
}
return {
	ConfettiBurst = ConfettiBurst,
}
