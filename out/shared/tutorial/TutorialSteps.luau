-- Compiled with roblox-ts v3.0.0
-- LA liste du tutorial, dans l'ordre. Éditer ici pour changer le déroulé.
-- L'`id` est la clé persistée : le renommer renvoie au début les joueurs qui y étaient.
-- Voir docs/superpowers/specs/2026-08-17-tutorial-system-design.md §10.
local TUTORIAL_STEPS = { {
	id = "go-to-button",
	text = "Go push your button",
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
	text = "Press START to launch your rocket !",
	target = {
		kind = "gui",
		path = "ButtonMenu/StartButton",
	},
	focus = "dim",
	run = {
		freezeAt = 5,
		advanceToOnFreeze = "claim",
		unfreezeOnClaim = true,
		explodeAfterClaim = 2,
		noRisk = true,
	},
	complete = {
		kind = "popup",
		popup = "RocketLaunch",
	},
}, {
	id = "watch-launch",
	text = "Your rocket is flying! The higher it goes, the bigger your multiplier",
	textY = 0.16,
	target = {
		kind = "none",
	},
	complete = {
		kind = "server",
	},
}, {
	id = "claim",
	text = "Press CLAIM to secure your cash",
	target = {
		kind = "gui",
		path = "RocketLaunch/ClaimButtonFrame/ClaimButton",
	},
	focus = "dim",
	textY = 0.16,
	complete = {
		kind = "event",
		event = "ClaimAccepted",
	},
}, {
	id = "claim-explode",
	text = "Cash secured! Even if the rocket blows up, you keep it all",
	textY = 0.16,
	target = {
		kind = "none",
	},
	complete = {
		kind = "popupClosed",
		popup = "ButtonFinishGame",
	},
}, {
	id = "go-to-shop",
	text = "Head to the shop to upgrade your rocket",
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
	text = "Buy Rocket Speed: your rocket will climb faster",
	target = {
		kind = "gui",
		path = "ShopMenu/Body/ARocketSpeed",
	},
	focus = "dim",
	textY = 0,
	complete = {
		kind = "attribute",
		attribute = "RocketSpeedLevel",
		increaseBy = 1,
	},
}, {
	id = "back-to-button",
	text = "Go back to your button and play again — you're on your own now!",
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
