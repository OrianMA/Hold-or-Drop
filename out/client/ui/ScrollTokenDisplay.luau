-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local TweenService = _services.TweenService
local FormatNumber = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatNumber
local SCROLL_TOKENS_ATTR = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "QuestConfig").SCROLL_TOKENS_ATTR
-- Compteur de ScrollToken du panneau des quêtes
-- (InGameUI/QuestsPanel/Header/ScrollTokenCount/ScrollCountText) — le pendant de
-- MoneyDisplay pour la seconde monnaie, en beaucoup plus simple.
--
-- L'attribut ScrollTokens est écrit par le serveur et se réplique ; on ne fait que
-- le rendre, en faisant DÉFILER le nombre au lieu de le remplacer d'un coup, pour
-- qu'un gain de quête comme une dépense en boutique se voient passer.
--
-- `spend(amount)` ajoute la lecture d'une dépense : un « -350K » qui monte et
-- s'efface au-dessus du compteur, plus une petite claque d'échelle sur le compteur.
-- Le label volant est un CLONE du compteur : il hérite police, taille et contour,
-- donc il reste juste même si le style change en Studio.
local player = Players.LocalPlayer
local LABEL_NAME = "ScrollCountText"
local COUNTER_NAME = "ScrollTokenCount"
-- Défilement du nombre. Court : ce n'est pas le compteur d'argent, il ne doit pas
-- retenir l'attention aussi longtemps.
local COUNT_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Claque d'échelle du compteur à la dépense.
local PUNCH_SCALE = 1.18
local PUNCH_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Label volant « -N ».
local SPEND_COLOR = Color3.new(1, 0.45, 0.45)
local SPEND_RISE = 60
local SPEND_TWEEN = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local label
local counter
local counterScale
local screenGui
local proxy
local displayed = 0
local activeTween
local function tokens()
	local _condition = (player:GetAttribute(SCROLL_TOKENS_ATTR))
	if _condition == nil then
		_condition = 0
	end
	return _condition
end
local function render(value)
	displayed = value
	if label then
		label.Text = FormatNumber(math.floor(value))
	end
end
-- Fait défiler l'affichage vers la valeur réelle de l'attribut.
local function refresh()
	local target = tokens()
	if not proxy then
		render(target)
		return nil
	end
	local _result = activeTween
	if _result ~= nil then
		_result:Cancel()
	end
	proxy.Value = displayed
	activeTween = TweenService:Create(proxy, COUNT_TWEEN, {
		Value = target,
	})
	activeTween:Play()
end
local ScrollTokenDisplay = {
	init = function(self)
		local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
		local header = inGameUI:WaitForChild("QuestsPanel"):WaitForChild("Header")
		local counterFrame = header:WaitForChild(COUNTER_NAME)
		screenGui = inGameUI
		counter = counterFrame
		label = counterFrame:WaitForChild(LABEL_NAME)
		-- UIScale posé à la volée côté client (identité à 1 : rien ne bouge tant qu'on
		-- ne joue pas la claque).
		local existing = counterFrame:FindFirstChildOfClass("UIScale")
		if existing then
			counterScale = existing
		else
			local scale = Instance.new("UIScale")
			scale.Parent = counterFrame
			counterScale = scale
		end
		proxy = Instance.new("NumberValue")
		proxy.Value = tokens()
		proxy.Changed:Connect(function(value)
			return render(value)
		end)
		render(tokens())
		player:GetAttributeChangedSignal(SCROLL_TOKENS_ATTR):Connect(refresh)
	end,
	spend = function(self, amount)
		if counterScale then
			local punchIn = TweenService:Create(counterScale, PUNCH_IN, {
				Scale = PUNCH_SCALE,
			})
			punchIn.Completed:Connect(function()
				if counterScale then
					TweenService:Create(counterScale, PUNCH_OUT, {
						Scale = 1,
					}):Play()
				end
			end)
			punchIn:Play()
		end
		if not label or not counter or not screenGui then
			return nil
		end
		-- Clone du compteur : même police, même contour, même taille — aucun style à
		-- dupliquer ici.
		local flying = label:Clone()
		flying.Name = "ScrollSpendText"
		flying.Text = `-{FormatNumber(amount)}`
		flying.TextColor3 = SPEND_COLOR
		flying.ZIndex = label.ZIndex + 10
		flying.AutomaticSize = Enum.AutomaticSize.None
		-- Positionné en pixels au-dessus du compteur : le label vit sous le ScreenGui,
		-- pas sous le compteur, sinon le UIListLayout du compteur le rangerait dans sa
		-- liste et décalerait l'icône.
		local _absolutePosition = counter.AbsolutePosition
		local _absolutePosition_1 = screenGui.AbsolutePosition
		local origin = _absolutePosition - _absolutePosition_1
		flying.Size = UDim2.new(0, counter.AbsoluteSize.X, 0, counter.AbsoluteSize.Y)
		flying.Position = UDim2.new(0, origin.X, 0, origin.Y)
		flying.BackgroundTransparency = 1
		flying.Parent = screenGui
		local rise = UDim2.new(0, origin.X, 0, origin.Y - SPEND_RISE)
		TweenService:Create(flying, SPEND_TWEEN, {
			Position = rise,
			TextTransparency = 1,
		}):Play()
		for _, child in flying:GetDescendants() do
			if child:IsA("UIStroke") then
				TweenService:Create(child, SPEND_TWEEN, {
					Transparency = 1,
				}):Play()
			end
		end
		task.delay(SPEND_TWEEN.Time, function()
			return flying:Destroy()
		end)
	end,
}
return {
	ScrollTokenDisplay = ScrollTokenDisplay,
}
