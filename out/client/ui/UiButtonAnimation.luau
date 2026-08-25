-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local TweenService = _services.TweenService
local UserInputService = _services.UserInputService
-- Animation de survol / clic centralisée pour TOUTE l'UI. Même principe que
-- UiClickSound : au lieu de câbler l'anim bouton par bouton, on accroche
-- automatiquement chaque GuiButton du PlayerGui — ceux déjà présents au
-- démarrage et ceux ajoutés plus tard (DescendantAdded). Tout nouveau bouton
-- créé en Studio est animé sans une ligne de code en plus.
--
-- 100 % client / présentation.
--
-- DEUX choix structurants :
--
-- 1. On anime la FRAME PARENTE, pas le bouton. Dans cette UI le GuiButton est
--    presque toujours une zone de clic transparente posée sur une Frame qui
--    porte tout le visuel (UICorner, UIStroke, UIGradient, TextLabel, sous-
--    frames) : ShopMoneyBuy/MoneyElementN/Button, QuestsPanel/…/BuyButtonFrame/
--    TextButton, HUD/ButtonsFrame/QuestsFrame/ImageButton… Scaler le bouton seul
--    ne bougerait rien de visible. Voir resolveTarget() pour la règle exacte et
--    les cas où on reste sur le bouton.
--
-- 2. On anime un UIScale, JAMAIS la propriété Size : plusieurs systèmes tweenent
--    déjà Size (le pulse du ClaimButton, la barre de progression) et le layout
--    (UIListLayout/UIGridLayout) est calculé sur Size. Le UIScale est purement
--    visuel, ne décale rien, et ne peut donc entrer en conflit avec personne.
--
-- Un bouton marqué avec l'attribut `NoUiAnim` est ignoré (échappatoire pour un
-- bouton qui aurait sa propre animation).
local SCALE_NAME = "UiAnimScale"
-- ScreenGui généré par Roblox pour les ProximityPrompts par défaut : UI système,
-- créée/détruite en continu — on n'y touche pas.
local IGNORED_SCREENGUI = "ProximityPrompts"
-- Facteurs appliqués par-dessus l'échelle d'origine de la cible.
local HOVER_SCALE = 1.07
local PRESS_SCALE = 0.92
-- Survol : entrée avec un léger dépassement (Back), sortie neutre et douce.
local HOVER_IN_TI = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT_TI = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Appui : très court, pour que l'enfoncement colle au doigt / au clic.
local PRESS_TI = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Relâche : le "pop" satisfaisant — rebond au-delà de la cible puis retour.
local RELEASE_TI = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Le bouton doit couvrir au moins cette fraction de sa frame parente pour qu'on
-- considère qu'il « est » cette frame (et donc qu'on anime la frame).
local FILL_THRESHOLD = 0.75
local states = {}
-- Un seul bouton est survolé/pressé à la fois : on ne surveille que celui-là.
local activeState
local watchConn
-- Quoi faire grossir : la frame parente quand le bouton n'est qu'une hitbox
-- posée dessus, sinon le bouton lui-même.
--
-- On remonte au parent seulement si les deux conditions tiennent :
--   • le parent ne contient QU'UN seul GuiButton — sinon survoler BuyButton
--     ferait aussi grossir RobuxButton (ShopMenu/…/ButtonsLayout) ;
--   • le bouton remplit son parent — sinon on ferait grossir tout un Header
--     (ShopMenu/Header/CloseButton) ou toute une popup (ButtonMenu/StartButton).
local function resolveTarget(button)
	local parent = button.Parent
	if parent == nil or not parent:IsA("GuiObject") then
		return button
	end
	local size = button.Size
	local fills = size.X.Scale >= FILL_THRESHOLD and size.Y.Scale >= FILL_THRESHOLD and size.X.Offset <= 0 and size.Y.Offset <= 0
	if not fills then
		return button
	end
	for _, child in parent:GetChildren() do
		if child ~= button and child:IsA("GuiButton") then
			return button
		end
	end
	return parent
end
local function targetScale(state)
	if state.pressed then
		return state.base * PRESS_SCALE
	end
	if state.hovered then
		return state.base * HOVER_SCALE
	end
	return state.base
end
local function animate(state, info)
	local _result = state.tween
	if _result ~= nil then
		_result:Cancel()
	end
	local _result_1 = state.tween
	if _result_1 ~= nil then
		_result_1:Destroy()
	end
	local tween = TweenService:Create(state.scale, info, {
		Scale = targetScale(state),
	})
	state.tween = tween
	tween:Play()
end
-- Retour immédiat au repos, sans tween — pour les cas où l'élément disparaît
-- alors qu'il est survolé/pressé (fermeture de popup) et ne recevra jamais son
-- MouseLeave : il ne doit pas réapparaître agrandi.
local function reset(state)
	state.hovered = false
	state.pressed = false
	local _result = state.tween
	if _result ~= nil then
		_result:Cancel()
	end
	local _result_1 = state.tween
	if _result_1 ~= nil then
		_result_1:Destroy()
	end
	state.tween = nil
	state.scale.Scale = state.base
end
-- Visibilité *effective* : le bouton lui-même, tous ses ancêtres GuiObject, et
-- le ScreenGui qui les porte.
local function isShown(button)
	local node = button
	while node ~= nil do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end
-- Roblox ne déclenche PAS MouseLeave quand un ancêtre passe en Visible = false
-- (fermeture de popup). Sans ce garde-fou l'élément resterait figé agrandi et
-- réapparaîtrait ainsi à la réouverture. Tant qu'un bouton est actif, on vérifie
-- chaque frame qu'il est toujours à l'écran — une seule connexion, quelques
-- ancêtres à remonter.
local function setActive(state)
	activeState = state
	if state == nil then
		local _result = watchConn
		if _result ~= nil then
			_result:Disconnect()
		end
		watchConn = nil
		return nil
	end
	if watchConn ~= nil then
		return nil
	end
	watchConn = RunService.Heartbeat:Connect(function()
		local current = activeState
		if current == nil then
			return nil
		end
		if isShown(current.button) then
			return nil
		end
		reset(current)
		setActive(nil)
	end)
end
local function hook(instance)
	if not instance:IsA("GuiButton") then
		return nil
	end
	local _instance = instance
	if states[_instance] ~= nil then
		return nil
	end
	if instance:GetAttribute("NoUiAnim") == true then
		return nil
	end
	if instance:FindFirstAncestor(IGNORED_SCREENGUI) ~= nil then
		return nil
	end
	local button = instance
	local target = resolveTarget(button)
	-- Réutilise un UIScale déjà présent (posé en Studio pour le style) plutôt que
	-- d'en ajouter un second : Roblox n'en applique qu'un seul par GuiObject.
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = SCALE_NAME
		scale.Parent = target
	end
	local state = {
		button = button,
		scale = scale,
		base = scale.Scale,
		hovered = false,
		pressed = false,
	}
	states[button] = state
	button.MouseEnter:Connect(function()
		state.hovered = true
		setActive(state)
		animate(state, HOVER_IN_TI)
	end)
	button.MouseLeave:Connect(function()
		-- Sortir du bouton annule aussi l'appui : relâcher dehors ne doit pas
		-- laisser l'élément enfoncé.
		state.hovered = false
		state.pressed = false
		if activeState == state then
			setActive(nil)
		end
		animate(state, HOVER_OUT_TI)
	end)
	button.MouseButton1Down:Connect(function()
		state.pressed = true
		setActive(state)
		animate(state, PRESS_TI)
	end)
	button.MouseButton1Up:Connect(function()
		state.pressed = false
		animate(state, RELEASE_TI)
	end)
	-- Navigation manette : le focus se comporte comme un survol.
	button.SelectionGained:Connect(function()
		state.hovered = true
		setActive(state)
		animate(state, HOVER_IN_TI)
	end)
	button.SelectionLost:Connect(function()
		state.hovered = false
		if activeState == state then
			setActive(nil)
		end
		animate(state, HOVER_OUT_TI)
	end)
	button.Destroying:Connect(function()
		if activeState == state then
			setActive(nil)
		end
		states[button] = nil
	end)
end
local function init()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, desc in gui:GetDescendants() do
		hook(desc)
	end
	gui.DescendantAdded:Connect(hook)
	-- Filet de sécurité : un clic relâché hors du bouton ne déclenche pas
	-- MouseButton1Up sur celui-ci. On dépresse alors tout ce qui traîne.
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return nil
		end
		-- ▼ ReadonlyMap.forEach ▼
		local _callback = function(state)
			if not state.pressed then
				return nil
			end
			state.pressed = false
			animate(state, RELEASE_TI)
		end
		for _k, _v in states do
			_callback(_v, _k, states)
		end
		-- ▲ ReadonlyMap.forEach ▲
	end)
end
return {
	init = init,
}
