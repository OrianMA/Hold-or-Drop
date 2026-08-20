-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local MarketplaceService = _services.MarketplaceService
local Players = _services.Players
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local FormatCash = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "NumberFormat").FormatCash
local _DailyRewardConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "DailyRewardConfig")
local DAILY_AUTO_OPEN_ATTR = _DailyRewardConfig.DAILY_AUTO_OPEN_ATTR
local DAILY_CLAIMED_ATTR = _DailyRewardConfig.DAILY_CLAIMED_ATTR
local DAILY_MULTIPLIER_ATTR = _DailyRewardConfig.DAILY_MULTIPLIER_ATTR
local DAILY_X3_PRODUCT_ID = _DailyRewardConfig.DAILY_X3_PRODUCT_ID
local InGameUIController = TS.import(script, script.Parent.Parent, "ui", "InGameUIController").InGameUIController
local MoneyBurst = TS.import(script, script.Parent.Parent, "ui", "MoneyBurst").MoneyBurst
local FloatingReward = TS.import(script, script.Parent.Parent, "ui", "FloatingReward").FloatingReward
local playCashSound = TS.import(script, script.Parent.Parent, "audio", "CashSound").playCashSound
local InformationText = TS.import(script, script.Parent.Parent, "ui", "InformationText").InformationText
local DailyRewardsAnimation = TS.import(script, script.Parent.Parent, "ui", "DailyRewardsAnimation").DailyRewardsAnimation
local TutorialUI = TS.import(script, script.Parent.Parent, "tutorial", "TutorialUI").TutorialUI
-- Opens / closes the daily reward popup (InGameUI/DailyRewards) and renders it.
--   • HUD/ButtonsFrame/DailyRewardsFrame/ImageButton opens it at any time.
--   • the replicated DailyAutoOpen attribute opens it by itself — on join with a
--     pending reward, or on the first rebirth of a brand-new player.
--   • Header/CloseButtonFrame/CloseButton closes it.
-- Opening hides the persistent HUD (mirrors ShopBehavior / RebirthMenuBehavior).
--
-- Everything shown is read from the replicated attributes DailyMultiplier /
-- DailyClaimed + EffectiveBaseCash — no round-trip. The grant itself is fully
-- re-validated server-side (DailyRewardService).
local POPUP_NAME = "DailyRewards"
local CLAIMED_LABEL = "Claimed"
-- Menus the popup takes the screen from when it opens by itself. The first-rebirth
-- auto-open in particular lands while the Rebirth menu is still up — leaving it
-- behind would restore the HUD on top of it when the popup closes. They are plain
-- open/close frames with no state of their own, so hiding them here is safe.
local MENUS_TO_HIDE = { "RebirthMenu", "ShopMenu", "ShopMoneyBuy" }
-- Une ouverture AUTOMATIQUE ne vole pas l'écran à un menu que le joueur est en train
-- de lire : elle attend qu'il le referme, puis laisse passer ce temps mort avant de
-- s'afficher. Le cas qui compte est le premier rebirth — le popup est déclenché
-- pendant que le menu Rebirth est encore ouvert sur l'écran de résultat.
local AUTO_OPEN_AFTER_MENU_DELAY = 1.5
local MENU_POLL = 0.2
-- Greyed-out tint applied to a button while today's reward is already taken.
local DISABLED_COLOR = Color3.new(0.45, 0.45, 0.45)
local REWARD_COLOR = Color3.new(0.45, 1, 0.55)
local function readButton(frame)
	local button = frame:WaitForChild("Button")
	local label = button:WaitForChild("TextLabel")
	return {
		button = button,
		label = label,
		baseColor = button.BackgroundColor3,
		baseText = label.Text,
	}
end
-- Enabled = the authored colour + text; disabled = grey, non-interactive, "Claimed"
-- on the free button (the ×3 keeps its own label — it just can't be bought again today).
local function setEnabled(entry, enabled, claimedLabel)
	entry.button.Interactable = enabled
	entry.button.AutoButtonColor = enabled
	entry.button.BackgroundColor3 = if enabled then entry.baseColor else DISABLED_COLOR
	local _result
	if enabled then
		_result = entry.baseText
	else
		local _condition = claimedLabel
		if _condition == nil then
			_condition = entry.baseText
		end
		_result = _condition
	end
	entry.label.Text = _result
end
local function init()
	local player = Players.LocalPlayer
	local inGameUI = (player:WaitForChild("PlayerGui")):WaitForChild("InGameUI")
	local popup = inGameUI:WaitForChild(POPUP_NAME)
	local closeButton = popup:WaitForChild("Header"):WaitForChild("CloseButtonFrame"):WaitForChild("CloseButton")
	local header = popup:WaitForChild("Header")
	local body = popup:WaitForChild("Body")
	local dailyCashTitle = body:WaitForChild("DailyCashTitle")
	local dailyCashValue = body:WaitForChild("DailyCashValue")
	local baseCashTitle = body:WaitForChild("BaseCashTitle")
	local baseCashValue = body:WaitForChild("BaseCashValue")
	local multiplierTitle = body:WaitForChild("DailyBonusMultiplierTitle")
	local multiplierValue = body:WaitForChild("DailyBonusMultiplierValue")
	local buttonsFrame = popup:WaitForChild("ButtonsFrame")
	local claimFrame = buttonsFrame:WaitForChild("ClaimButtonFrame")
	local claimX3Frame = buttonsFrame:WaitForChild("X3ClaimButtonFrame")
	local claim = readButton(claimFrame)
	local claimX3 = readButton(claimX3Frame)
	-- Everything the opening animation cascades in, in authored order — it re-sorts
	-- them by their real vertical position (see DailyRewardsAnimation.sortKey).
	local refs = {
		popup = popup,
		rows = { header, dailyCashTitle, dailyCashValue, baseCashValue, baseCashTitle, multiplierValue, multiplierTitle, claimFrame, claimX3Frame },
		totalLabel = dailyCashValue,
		multiplierLabel = multiplierValue,
	}
	local hud = inGameUI:WaitForChild("HUD")
	local openButton = hud:WaitForChild("ButtonsFrame"):WaitForChild("DailyRewardsFrame"):WaitForChild("ImageButton")
	popup.Visible = false
	local multiplier = function()
		local _condition = (player:GetAttribute(DAILY_MULTIPLIER_ATTR))
		if _condition == nil then
			_condition = 1
		end
		return _condition
	end
	local baseCash = function()
		local _condition = (player:GetAttribute("EffectiveBaseCash"))
		if _condition == nil then
			_condition = 0
		end
		return _condition
	end
	local claimed = function()
		return player:GetAttribute(DAILY_CLAIMED_ATTR) == true
	end
	-- Writes the three numbers + the button states from the current attributes.
	-- Called on open and whenever the server changes them while the popup is up.
	local render = function()
		local mult = multiplier()
		local base = baseCash()
		baseCashValue.Text = `${FormatCash(base)}`
		multiplierValue.Text = `{mult}x`
		dailyCashValue.Text = `${FormatCash(math.floor(base * mult))}`
		local available = not claimed()
		setEnabled(claim, available, CLAIMED_LABEL)
		setEnabled(claimX3, available)
	end
	local animationValues = function()
		return {
			baseCash = baseCash(),
			multiplier = multiplier(),
			animateCounters = not claimed(),
		}
	end
	local open = function()
		for _, name in MENUS_TO_HIDE do
			local menu = inGameUI:FindFirstChild(name)
			local _result = menu
			if _result ~= nil then
				_result = _result:IsA("GuiObject")
			end
			if _result then
				menu.Visible = false
			end
		end
		render()
		popup.Visible = true
		InGameUIController:disable()
		-- The popup can land mid-tutorial (a returning player who never finished it):
		-- hide the tutorial overlay so its dim doesn't darken the popup.
		TutorialUI:setSuppressed(true)
		DailyRewardsAnimation:play(refs, animationValues())
	end
	local close = function()
		-- Drop a running sequence first, otherwise a row could stay half-faded the
		-- next time the popup shows.
		DailyRewardsAnimation:stop(refs, animationValues())
		popup.Visible = false
		InGameUIController:enable()
		TutorialUI:setSuppressed(false)
	end
	openButton.Activated:Connect(open)
	closeButton.Activated:Connect(close)
	-- Le joueur est-il revenu à un écran neutre ? Aucun menu ouvert ET le HUD affiché.
	-- Après un rebirth le menu Rebirth reste ouvert et le HUD est masqué : le popup
	-- attend que le joueur ait refermé et soit bien retombé sur son HUD.
	local backOnHud = function()
		if not hud.Visible then
			return false
		end
		for _, name in MENUS_TO_HIDE do
			local menu = inGameUI:FindFirstChild(name)
			local _result = menu
			if _result ~= nil then
				_result = _result:IsA("GuiObject")
			end
			local _condition = _result
			if _condition then
				_condition = menu.Visible
			end
			if _condition then
				return false
			end
		end
		return true
	end
	-- Auto-open : le serveur incrémente DailyAutoOpen quand il veut voir le popup —
	-- avant qu'on arrive ici (connexion) ou plus tard (premier rebirth). On ouvre dès
	-- que le compteur dépasse celui qu'on a déjà traité, ce qui donne le "une fois par
	-- demande" sans latch : le serveur ne demande qu'une fois.
	local handledToken = 0
	local autoOpen = function()
		local _condition = (player:GetAttribute(DAILY_AUTO_OPEN_ATTR))
		if _condition == nil then
			_condition = 0
		end
		local token = _condition
		if token <= handledToken then
			return nil
		end
		handledToken = token
		task.spawn(function()
			if not backOnHud() then
				while not backOnHud() do
					task.wait(MENU_POLL)
				end
				task.wait(AUTO_OPEN_AFTER_MENU_DELAY)
			end
			open()
		end)
	end
	player:GetAttributeChangedSignal(DAILY_AUTO_OPEN_ATTR):Connect(autoOpen)
	autoOpen()
	claim.button.Activated:Connect(function()
		if claimed() then
			return nil
		end
		-- Lock both buttons right away: the attribute only flips once the server
		-- answers, and a double click would fire the event twice.
		setEnabled(claim, false, CLAIMED_LABEL)
		setEnabled(claimX3, false)
		Events.DailyRewardClaimEvent:FireServer()
	end)
	claimX3.button.Activated:Connect(function()
		if claimed() then
			return nil
		end
		MarketplaceService:PromptProductPurchase(player, DAILY_X3_PRODUCT_ID)
	end)
	-- Centre du compteur d'argent du HUD, en coordonnées écran absolues — la cible vers
	-- laquelle les billets convergent. Résolue au moment de l'aspiration : le HUD est
	-- masqué pendant que le popup est ouvert, il est de retour quand les billets partent.
	local moneyCounterCenter = function()
		local moneyParent = InGameUIController:getMoneyParent()
		if not moneyParent then
			return nil
		end
		local _absolutePosition = moneyParent.AbsolutePosition
		local _arg0 = moneyParent.AbsoluteSize / 2
		return _absolutePosition + _arg0
	end
	-- Server confirmed the grant (free claim or ×3 receipt): close the popup and
	-- flash what was earned.
	Events.DailyRewardGrantedEvent.OnClientEvent:Connect(function(amount, mult, bonus)
		-- A ×3 receipt can land after the player closed the popup — only take the
		-- screen back if we still own it.
		if popup.Visible then
			close()
		end
		-- Exactement la gerbe de billets du claim (§6.21) + son son de cash, à ceci
		-- près qu'ici les billets finissent aspirés dans le compteur d'argent.
		playCashSound()
		MoneyBurst:play(nil, {
			gatherTo = moneyCounterCenter,
		})
		-- Et le même "+montant" léger que la récompense de consolation d'une explosion
		-- (§6.4) — en version sans crédit : le serveur a déjà encaissé le gain.
		FloatingReward:showAlreadyCredited(amount, "fly")
		local suffix = if bonus > 1 then ` (x{mult} x{bonus})` else ` (x{mult})`
		InformationText:show(`Daily reward +${FormatCash(amount)}{suffix}`, {
			color = REWARD_COLOR,
		})
	end)
	-- Keep an open popup in sync if the numbers move underneath it. This is not
	-- theoretical: BoostService resolves group + game-pass ownership asynchronously,
	-- so EffectiveBaseCash routinely lands a second after join — right while the
	-- auto-opened popup is revealing. Re-running the whole sequence (rather than just
	-- rewriting the labels) keeps the count-up aiming at the right total.
	local shown = `{baseCash()}|{multiplier()}|{claimed()}`
	for _, attribute in { DAILY_CLAIMED_ATTR, DAILY_MULTIPLIER_ATTR, "EffectiveBaseCash" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local current = `{baseCash()}|{multiplier()}|{claimed()}`
			if current == shown then
				return nil
			end
			shown = current
			if not popup.Visible then
				return nil
			end
			render()
			DailyRewardsAnimation:play(refs, animationValues())
		end)
	end
end
return {
	init = init,
}
