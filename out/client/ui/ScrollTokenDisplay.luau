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
-- s'efface, plus une petite claque d'échelle sur le compteur. Le texte volant est
-- **centré en X sur le panneau** (et non collé au compteur, coincé dans un coin) :
-- c'est le milieu de l'écran de la boutique, donc là où le regard est déjà.
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
-- Le panneau entier : il ne sert qu'à donner sa largeur au texte volant, pour le
-- centrer horizontalement dessus.
local panel
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
		local questsPanel = inGameUI:WaitForChild("QuestsPanel")
		local header = questsPanel:WaitForChild("Header")
		local counterFrame = header:WaitForChild(COUNTER_NAME)
		screenGui = inGameUI
		panel = questsPanel
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
		if not label or not counter or not screenGui or not panel then
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
		-- Le compteur est ancré en son centre : sans remettre l'ancre en haut-à-gauche,
		-- la position posée plus bas placerait le MILIEU du label là où on veut son coin,
		-- soit un décalage d'une demi-largeur de panneau.
		flying.AnchorPoint = Vector2.new(0, 0)
		-- Positionné en pixels : le label vit sous le ScreenGui, pas sous le compteur,
		-- sinon le UIListLayout du compteur le rangerait dans sa liste et décalerait
		-- l'icône. Il est large comme le PANNEAU et centre son texte, ce qui le pose
		-- pile au milieu en X quelle que soit la résolution ; la hauteur reste celle du
		-- compteur, donc il part du bandeau du haut.
		local panelLeft = panel.AbsolutePosition.X - screenGui.AbsolutePosition.X
		local originY = counter.AbsolutePosition.Y - screenGui.AbsolutePosition.Y
		flying.Size = UDim2.new(0, panel.AbsoluteSize.X, 0, counter.AbsoluteSize.Y)
		flying.Position = UDim2.new(0, panelLeft, 0, originY)
		flying.TextXAlignment = Enum.TextXAlignment.Center
		flying.BackgroundTransparency = 1
		flying.Parent = screenGui
		local rise = UDim2.new(0, panelLeft, 0, originY - SPEND_RISE)
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
