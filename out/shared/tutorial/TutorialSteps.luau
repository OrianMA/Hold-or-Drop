-- Compiled with roblox-ts v3.0.0
-- LA liste du tutorial, dans l'ordre. Éditer ici pour changer le déroulé.
-- L'`id` est la clé persistée : le renommer renvoie au début les joueurs qui y étaient.
-- Voir docs/superpowers/specs/2026-08-17-tutorial-system-design.md §10.
local TUTORIAL_STEPS = { {
	id = "go-to-button",
	text = "Va appuyer sur ton bouton !",
	target = {
		kind = "world",
		part = "RoomButton",
	},
	complete = {
		kind = "event",
		event = "ButtonTrigger",
	},
}, {
	id = "press-start",
	text = "Appuie sur START pour faire décoller ta fusée",
	target = {
		kind = "gui",
		path = "ButtonMenu/StartButton",
	},
	focus = "dim",
	run = {
		freezeAt = 2.5,
		advanceToOnFreeze = "claim",
		unfreezeOnClaim = true,
		explodeAfterClaim = 1,
		noRisk = true,
	},
	complete = {
		kind = "popup",
		popup = "RocketLaunch",
	},
}, {
	id = "watch-launch",
	text = "Ta fusée décolle ! Plus elle monte, plus ton multiplicateur grimpe",
	target = {
		kind = "none",
	},
	complete = {
		kind = "server",
	},
}, {
	id = "claim",
	text = "Appuie sur CLAIM pour sécuriser tes gains",
	target = {
		kind = "gui",
		path = "RocketLaunch/ClaimButtonFrame/ClaimButton",
	},
	focus = "highlight",
	complete = {
		kind = "event",
		event = "ClaimAccepted",
	},
}, {
	id = "claim-explode",
	text = "Gains sécurisés ! Même si la fusée explose, tu gardes tout",
	target = {
		kind = "none",
	},
	complete = {
		kind = "popupClosed",
		popup = "ButtonFinishGame",
	},
}, {
	id = "go-to-shop",
	text = "Direction la boutique pour améliorer ta fusée",
	target = {
		kind = "world",
		part = "Shop",
	},
	complete = {
		kind = "popup",
		popup = "ShopMenu",
	},
}, {
	id = "buy-rocket-speed",
	text = "Achète Rocket Speed : ta fusée montera plus vite",
	target = {
		kind = "gui",
		path = "ShopMenu/Body/ARocketSpeed",
	},
	focus = "dim",
	complete = {
		kind = "attribute",
		attribute = "RocketSpeedLevel",
		increaseBy = 1,
	},
}, {
	id = "back-to-button",
	text = "Retourne à ton bouton et rejoue — à toi de jouer !",
	target = {
		kind = "world",
		part = "RoomButton",
	},
	complete = {
		kind = "event",
		event = "ButtonTrigger",
	},
} }
local function stepIndexById(id)
	for i = 0, #TUTORIAL_STEPS - 1 do
		if TUTORIAL_STEPS[i + 1].id == id then
			return i
		end
	end
	return nil
end
local function stepById(id)
	local index = stepIndexById(id)
	return if index ~= nil then TUTORIAL_STEPS[index + 1] else nil
end
local function firstStepId()
	return TUTORIAL_STEPS[1].id
end
return {
	stepIndexById = stepIndexById,
	stepById = stepById,
	firstStepId = firstStepId,
	TUTORIAL_STEPS = TUTORIAL_STEPS,
}
