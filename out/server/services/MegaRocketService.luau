-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local Events = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "Event").Events
local RoomService = TS.import(script, game:GetService("ServerScriptService"), "TS", "rooms", "RoomService").RoomService
local _CheatConfig = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "CheatConfig")
local megaRocketCheatDelay = _CheatConfig.megaRocketCheatDelay
local megaRocketCheatKey = _CheatConfig.megaRocketCheatKey
local megaRocketInterval = _CheatConfig.megaRocketInterval
local RocketLauncher = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketLauncher").RocketLauncher
local RocketPlacer = TS.import(script, game:GetService("ServerScriptService"), "TS", "modules", "RocketPlacer").RocketPlacer
local _MegaRocketConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "MegaRocketConfig")
local MEGA_ROCKET_ANNOUNCE = _MegaRocketConfig.MEGA_ROCKET_ANNOUNCE
local MEGA_ROCKET_ATTR = _MegaRocketConfig.MEGA_ROCKET_ATTR
local MEGA_ROCKET_INTERVAL = _MegaRocketConfig.MEGA_ROCKET_INTERVAL
local MEGA_ROCKET_PANEL_FIRED = _MegaRocketConfig.MEGA_ROCKET_PANEL_FIRED
local megaRocketPanelText = _MegaRocketConfig.megaRocketPanelText
-- Horloge de l'événement Mega Rocket (§6.24). Une seule boucle serveur pour tout
-- le serveur : elle écrit le compte à rebours sur le panneau de l'Environment et,
-- toutes les MEGA_ROCKET_INTERVAL secondes, donne sa Mega Rocket à chaque joueur.
--
-- Au top de l'événement :
--   • tout le monde reçoit l'attribut MegaRocket ;
--   • les fusées encore AU SOL sont reposées tout de suite en version mega ;
--   • celles DÉJÀ EN VOL ne sont pas touchées — leur run en cours reste normal et
--     c'est la fusée suivante qui sera mega (RocketPlacer la repose en fin de vol,
--     l'attribut étant toujours posé).
--
-- Le panneau est écrit côté serveur : c'est une TextLabel de Workspace, elle se
-- réplique donc telle quelle à tout le monde — pas de RemoteEvent, pas de contrôleur
-- client à synchroniser.
local PANEL_PART = "DisplayEventPanel"
local PANEL_LABEL = "EventText"
-- Temps pendant lequel le panneau affiche « MEGA ROCKET ! » avant de repartir en
-- compte à rebours.
local FIRED_TEXT_DURATION = 5
-- Intervalle réel entre deux événements — raccourcissable pour les tests
-- (CheatConfig.megaRocketInterval).
local _condition = megaRocketInterval
if _condition == nil then
	_condition = MEGA_ROCKET_INTERVAL
end
local INTERVAL = _condition
-- Instant (os.clock) du prochain événement.
local nextEventAt = 0
-- Tant que cet instant n'est pas passé, la boucle laisse « MEGA ROCKET ! » sur le
-- panneau au lieu d'y réécrire le compte à rebours. C'est ce qui permet de déclencher
-- l'événement DEPUIS L'EXTÉRIEUR de la boucle (achat ScrollToken, §6.27) sans que la
-- seconde suivante n'efface le message.
local panelHoldUntil = 0
local function findPanelLabel()
	local environment = Workspace:FindFirstChild("Environment")
	local _panel = environment
	if _panel ~= nil then
		_panel = _panel:FindFirstChild(PANEL_PART)
	end
	local panel = _panel
	local _gui = panel
	if _gui ~= nil then
		_gui = _gui:FindFirstChildOfClass("SurfaceGui")
	end
	local gui = _gui
	-- Recherche RÉCURSIVE : le label vit sous un Frame de fond (MegaRocketFrame) et
	-- peut être ré-emboîté en Studio sans casser le code.
	local _label = gui
	if _label ~= nil then
		_label = _label:FindFirstChild(PANEL_LABEL, true)
	end
	local label = _label
	return if label ~= nil and label:IsA("TextLabel") then label else nil
end
local function setPanelText(text)
	local label = findPanelLabel()
	if label then
		label.Text = text
	end
end
-- Top de l'événement : tout le monde gagne sa Mega Rocket.
-- `announce` remplace le bandeau par défaut — un déclenchement acheté annonce QUI l'a
-- payé plutôt que le message d'horloge.
local function fireEvent(announce)
	if announce == nil then
		announce = MEGA_ROCKET_ANNOUNCE
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute(MEGA_ROCKET_ATTR, true)
	end
	-- Bandeau légendaire pour tout le serveur (§6.20).
	Events.InformationTextEvent:FireAllClients(announce, {
		rarity = "Legendary",
	})
	-- Fusées au sol → elles deviennent mega immédiatement. Un rig qui n'est pas sur
	-- son pad (vol en cours, explosion, retour "Go Home" en attente) n'est JAMAIS
	-- touché : c'est son replacement de fin de vol qui posera la mega.
	for _, room in RoomService:getRooms() do
		if not room:getOccupant() then
			continue
		end
		if not RocketLauncher:isAtPad(room) then
			continue
		end
		RocketPlacer:place(room)
	end
end
local MegaRocketService = {
	init = function(self)
		nextEventAt = os.clock() + INTERVAL
		setPanelText(megaRocketPanelText(INTERVAL))
		-- Cheat de dev : la touche G du client ramène le compte à rebours à
		-- `megaRocketCheatDelay` secondes (voir CheatConfig / client/MegaRocketCheat).
		-- L'event n'est même pas branché quand le cheat est éteint. Seule la prochaine
		-- échéance bouge : l'événement d'après repart sur l'intervalle normal.
		if megaRocketCheatKey then
			Events.MegaRocketCheatEvent.OnServerEvent:Connect(function()
				nextEventAt = os.clock() + megaRocketCheatDelay
				setPanelText(megaRocketPanelText(megaRocketCheatDelay))
			end)
		end
		task.spawn(function()
			while true do
				task.wait(1)
				-- Un déclenchement acheté vient d'écrire « MEGA ROCKET ! » : on ne touche
				-- pas au panneau tant que son temps d'affichage n'est pas écoulé.
				if os.clock() < panelHoldUntil then
					continue
				end
				if os.clock() >= nextEventAt then
					-- `nextEventAt` est absolu : l'affichage de « MEGA ROCKET ! » ci-dessous
					-- ne décale donc pas la cadence de l'événement suivant.
					nextEventAt = os.clock() + INTERVAL
					fireEvent()
					setPanelText(MEGA_ROCKET_PANEL_FIRED)
					task.wait(FIRED_TEXT_DURATION)
					continue
				end
				setPanelText(megaRocketPanelText(nextEventAt - os.clock()))
			end
		end)
	end,
	fireNow = function(self, announce)
		nextEventAt = os.clock() + INTERVAL
		fireEvent(announce)
		setPanelText(MEGA_ROCKET_PANEL_FIRED)
		panelHoldUntil = os.clock() + FIRED_TEXT_DURATION
	end,
	consume = function(self, player)
		player:SetAttribute(MEGA_ROCKET_ATTR, false)
	end,
}
return {
	MegaRocketService = MegaRocketService,
}
