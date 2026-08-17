-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local Players = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services").Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local TutorialUI = TS.import(script, script.Parent, "TutorialUI").TutorialUI
-- Surveille la condition de complétion d'un step et appelle onComplete UNE fois.
-- Tout est détecté avec ce que le client voit déjà : events serveur → client existants,
-- attributs répliqués, et visibilité des frames de InGameUI. Aucun nouvel event.
--
-- Le trigger "server" ne branche RIEN : c'est le serveur qui sort du step (run truqué).
local player = Players.LocalPlayer
local function findPopup(name)
	local root = TutorialUI:getInGameUI()
	local _found = root
	if _found ~= nil then
		_found = _found:FindFirstChild(name)
	end
	local found = _found
	local _result = found
	if _result ~= nil then
		_result = _result:IsA("GuiObject")
	end
	return if _result then found else nil
end
local TutorialTriggers = {
	watch = function(self, step, onComplete)
		local trigger = step.complete
		local done = false
		local fire = function()
			if done then
				return nil
			end
			done = true
			onComplete()
		end
		if trigger.kind == "server" then
			return function() end
		end
		if trigger.kind == "event" then
			local conn = if trigger.event == "ButtonTrigger" then Events.ButtonTriggerEvent.OnClientEvent:Connect(function()
				return fire()
			end) else Events.ClaimAcceptedEvent.OnClientEvent:Connect(function()
				return fire()
			end)
			return function()
				return conn:Disconnect()
			end
		end
		if trigger.kind == "attribute" then
			-- Seuil RELATIF : un joueur existant a déjà des niveaux, on attend une hausse
			-- depuis l'entrée dans le step.
			local _condition = (player:GetAttribute(trigger.attribute))
			if _condition == nil then
				_condition = 0
			end
			local baseline = _condition
			local conn = player:GetAttributeChangedSignal(trigger.attribute):Connect(function()
				local _condition_1 = (player:GetAttribute(trigger.attribute))
				if _condition_1 == nil then
					_condition_1 = 0
				end
				local current = _condition_1
				if current >= baseline + trigger.increaseBy then
					fire()
				end
			end)
			return function()
				return conn:Disconnect()
			end
		end
		-- popup / popupClosed — la frame de InGameUI devient visible / invisible.
		local wantVisible = trigger.kind == "popup"
		local frame = findPopup(trigger.popup)
		if not frame then
			warn(`TutorialTriggers: frame "{trigger.popup}" introuvable sous InGameUI`)
			return function() end
		end
		-- popupClosed n'est valide qu'après une ouverture : sinon un step attendant la
		-- fermeture d'une popup déjà fermée passerait instantanément.
		local seenOpen = frame.Visible
		local conn = frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if frame.Visible then
				seenOpen = true
				if wantVisible then
					fire()
				end
				return nil
			end
			if not wantVisible and seenOpen then
				fire()
			end
		end)
		if wantVisible and frame.Visible then
			fire()
		end
		return function()
			return conn:Disconnect()
		end
	end,
}
return {
	TutorialTriggers = TutorialTriggers,
}
