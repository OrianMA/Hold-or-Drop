-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local ButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "ButtonModule").ButtonModule
local ButtonTriggerService = {
	init = function(self)
		local buttons = game.Workspace:FindFirstChild("Buttons")
		if not buttons then
			return nil
		end
		for _, buttonModel in buttons:GetChildren() do
			ButtonModule.new():init(buttonModel)
		end
	end,
}
return {
	ButtonTriggerService = ButtonTriggerService,
}
