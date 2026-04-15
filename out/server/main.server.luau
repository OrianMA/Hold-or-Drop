-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local makeHello = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "module").makeHello
local services = TS.import(script, game:GetService("ServerScriptService"), "TS", "services").services
print(makeHello("main.server.ts"))
for _, service in services do
	service:init()
end
