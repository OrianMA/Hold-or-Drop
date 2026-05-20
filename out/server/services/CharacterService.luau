-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local SCALE = {
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
}
local function normalizeSize(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
	desc.HeightScale = SCALE.HeightScale
	desc.WidthScale = SCALE.WidthScale
	desc.DepthScale = SCALE.DepthScale
	desc.HeadScale = SCALE.HeadScale
	humanoid:ApplyDescription(desc)
end
local CharacterService = {
	init = function(self)
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(function(character)
				return normalizeSize(player, character)
			end)
		end)
		-- Handle players already in-game (e.g. during Studio testing)
		for _, player in Players:GetPlayers() do
			player.CharacterAdded:Connect(function(character)
				return normalizeSize(player, character)
			end)
			if player.Character then
				normalizeSize(player, player.Character)
			end
		end
	end,
}
return {
	CharacterService = CharacterService,
}
