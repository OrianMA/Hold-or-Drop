-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local initButtonMenu = TS.import(script, script.Parent, "behaviors", "ButtonMenuBehavior").init
local _ButtonInGameBehavior = TS.import(script, script.Parent, "behaviors", "ButtonInGameBehavior")
local initButtonInGame = _ButtonInGameBehavior.init
local setupButtonInGame = _ButtonInGameBehavior.setup
initButtonInGame()
initButtonMenu(setupButtonInGame)
