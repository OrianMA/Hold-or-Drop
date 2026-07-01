-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local rebirthCost = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").rebirthCost
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
-- Authoritative rebirth. The client pre-checks affordability for instant
-- feedback, but the reset is fully re-validated here — never trust the client.
-- On success: Money → 0, the 3 stat levels → 0, Rebirths += 1 (MultRebirth grows).
-- Playtime is NEVER touched here — it drives the leaderboard and must survive rebirths.
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
local function handleRebirth(player)
	local rebirths = PlayerProgressionService:getRebirths(player)
	local cost = rebirthCost(rebirths)
	if PlayerDataService:get(player, "Money") < cost then
		Events.InformationTextEvent:FireClient(player, "Pas assez d'argent pour le Rebirth", DENIED_COLOR)
		return nil
	end
	PlayerDataService:set(player, "Money", 0)
	PlayerProgressionService:rebirth(player)
	-- The rebirth level just changed → swap the pad rocket for the new one instantly
	-- (otherwise the old rocket would linger until the player leaves/rejoins the room).
	local room = RoomService:getRoom(player)
	if room then
		RocketPlacer:place(room)
	end
end
local RebirthService = {
	init = function(self)
		Events.RebirthEvent.OnServerEvent:Connect(function(player)
			return handleRebirth(player)
		end)
	end,
	safeRebirth = function(self, player)
		PlayerProgressionService:safeRebirth(player)
		-- Swap the pad rocket for the new rebirth-level one. Wrapped in pcall: this
		-- runs inside ProcessReceipt, and a throw AFTER the Rebirths increment would
		-- make Roblox retry the receipt → double rebirth. The swap is cosmetic, so a
		-- failure here must never undo (or duplicate) the grant.
		local room = RoomService:getRoom(player)
		if room then
			pcall(function()
				return RocketPlacer:place(room)
			end)
		end
	end,
}
return {
	RebirthService = RebirthService,
}
