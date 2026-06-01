-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
-- Per-player "your base" BillboardGui visibility.
--
-- Each room has an OwnerDisplay/OwnerIndicatorPart/BillboardGui that should
-- only show for the room's owner. BillboardGui.Enabled is a global property, so
-- the server keeps it disabled (see Room.ts) and each client locally enables
-- only the indicator on their own room. Client writes to Enabled don't replicate,
-- so other players never see it. Same pattern as RoomPromptController.
local PLAYER_ZONES = "PlayerZones"
local OWNER_DISPLAY = "OwnerDisplay"
local OWNER_INDICATOR_PART = "OwnerIndicatorPart"
local ASSIGNED_ROOM_ATTR = "AssignedRoom"
local function init()
	local player = Players.LocalPlayer
	-- roomName ("P1") → its owner-indicator BillboardGui
	local billboards = {}
	local evaluate = function()
		local _condition = (player:GetAttribute(ASSIGNED_ROOM_ATTR))
		if _condition == nil then
			_condition = ""
		end
		local assigned = _condition
		for name, billboard in billboards do
			billboard.Enabled = name == assigned
		end
	end
	player:GetAttributeChangedSignal(ASSIGNED_ROOM_ATTR):Connect(evaluate)
	task.spawn(function()
		local zones = Workspace:WaitForChild(PLAYER_ZONES, 30)
		if not zones then
			warn("OwnerIndicatorController: Workspace/PlayerZones not found")
			return nil
		end
		local register = function(folder)
			local ownerDisplay = folder:WaitForChild(OWNER_DISPLAY, 10)
			local _indicatorPart = ownerDisplay
			if _indicatorPart ~= nil then
				_indicatorPart = _indicatorPart:WaitForChild(OWNER_INDICATOR_PART, 10)
			end
			local indicatorPart = _indicatorPart
			local _billboard = indicatorPart
			if _billboard ~= nil then
				_billboard = _billboard:FindFirstChildOfClass("BillboardGui")
			end
			local billboard = _billboard
			if billboard then
				billboard.Enabled = false
				local _name = folder.Name
				billboards[_name] = billboard
			else
				warn(`OwnerIndicatorController: no BillboardGui under {folder.Name}/{OWNER_DISPLAY}/{OWNER_INDICATOR_PART}`)
			end
		end
		for _, folder in zones:GetChildren() do
			register(folder)
		end
		evaluate()
		-- Late-added rooms (StreamingEnabled / runtime authoring).
		zones.ChildAdded:Connect(function(folder)
			return task.spawn(function()
				register(folder)
				evaluate()
			end)
		end)
	end)
end
return {
	init = init,
}
