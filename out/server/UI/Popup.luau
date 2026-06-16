-- Compiled with roblox-ts v3.0.0
local Popup
do
	Popup = setmetatable({}, {
		__tostring = function()
			return "Popup"
		end,
	})
	Popup.__index = Popup
	function Popup.new(...)
		local self = setmetatable({}, Popup)
		return self:constructor(...) or self
	end
	function Popup:constructor()
		self.className = ""
	end
	function Popup:GetPlayerFrame(player)
		local playerGui = player:WaitForChild("PlayerGui")
		local screenGui = playerGui:WaitForChild("InGameUI")
		local currentFrame = screenGui:WaitForChild(self.className)
		return currentFrame
	end
	function Popup:Show(player)
		self:GetPlayerFrame(player).Visible = true
	end
	function Popup:Hide(player)
		self:GetPlayerFrame(player).Visible = false
	end
end
return {
	Popup = Popup,
}
