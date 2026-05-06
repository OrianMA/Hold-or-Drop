-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local RunService = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").RunService
local function DefineEvent(event_name, parent)
	if RunService:IsClient() then
		return parent:WaitForChild(event_name)
	end
	local event = Instance.new("RemoteEvent", parent)
	event.Name = event_name
	return event
end
return {
	default = DefineEvent,
}
