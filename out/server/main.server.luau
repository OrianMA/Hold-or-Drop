-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local services = TS.import(script, game:GetService("ServerScriptService"), "TS", "services").services
print("Main.server init")
for _, service in services do
	service:init()
end
