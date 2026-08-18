-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local rebirthCost = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "ShopConfig").rebirthCost
local PlayerProgressionService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerProgressionService").PlayerProgressionService
local PlayerDataService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "PlayerDataService").PlayerDataService
local _AnalyticsService = TS.import(script, game:GetService("ServerScriptService"), "TS", "services", "AnalyticsService")
local AnalyticsService = _AnalyticsService.AnalyticsService
local TxType = _AnalyticsService.TxType
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
local EndGameButtonModule = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "EndGameButtonModule").EndGameButtonModule
-- Authoritative rebirth. The client pre-checks affordability for instant
-- feedback, but the reset is fully re-validated here — never trust the client.
-- On success: Money → 0, the 3 stat levels → 0, Rebirths += 1 (MultRebirth grows).
-- Playtime is NEVER touched here — it drives the leaderboard and must survive rebirths.
local DENIED_COLOR = Color3.new(1, 0.4, 0.4)
local function handleRebirth(player)
	local rebirths = PlayerProgressionService:getRebirths(player)
	local cost = rebirthCost(rebirths)
	local money = PlayerDataService:get(player, "Money")
	if money < cost then
		Events.InformationTextEvent:FireClient(player, "Pas assez d'argent pour le Rebirth", {
			color = DENIED_COLOR,
		})
		return nil
	end
	PlayerDataService:set(player, "Money", 0)
	PlayerProgressionService:rebirth(player)
	-- Analytics: the whole balance leaves the economy (Sink → 0) + progression milestone
	-- + custom counter + onboarding step 5. Read the fresh rebirth count for the level.
	local newRebirths = PlayerProgressionService:getRebirths(player)
	AnalyticsService:cashSink(player, money, 0, TxType.Rebirth, `Rebirth{newRebirths}`)
	AnalyticsService:rebirth(player, newRebirths)
	AnalyticsService:custom(player, "RebirthDone", newRebirths)
	AnalyticsService:onboardingStep(player, 5, "Rebirth")
	-- Drop any payout that was still animating: cancel the server credit so it can't
	-- land after the reset to 0, and tell the client to remove the in-flight floating
	-- texts flying toward the money HUD (FloatingCash).
	EndGameButtonModule:cancelPending(player)
	Events.RebirthResetEvent:FireClient(player)
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
		-- Analytics: progression milestone + custom counter (Robux-paid, keeps progression).
		local newRebirths = PlayerProgressionService:getRebirths(player)
		AnalyticsService:rebirth(player, newRebirths)
		AnalyticsService:custom(player, "SafeRebirthDone", newRebirths)
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
