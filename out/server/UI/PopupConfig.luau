-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local PopupType = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "PopupType").PopupType
local ButtonInGamePopup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupBehaviors", "ButtonInGamePopup").ButtonInGamePopup
local ButtonMenuPopup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupBehaviors", "ButtonMenuPopup").ButtonMenuPopup
local ButtonFinishGamePopup = TS.import(script, game:GetService("ServerScriptService"), "TS", "UI", "PopupBehaviors", "ButtonFinishGamePopup").ButtonFinishGamePopup
local PopupConfig = { {
	type = PopupType.ButtonMenu,
	frameName = "ButtonMenu",
	class = ButtonMenuPopup,
}, {
	type = PopupType.ButtonInGame,
	frameName = "ButtonInGame",
	class = ButtonInGamePopup,
}, {
	type = PopupType.ButtonFinishGame,
	frameName = "ButtonFinishGame",
	class = ButtonFinishGamePopup,
} }
return {
	PopupConfig = PopupConfig,
}
