-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local SoundService = _services.SoundService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Les sons 2D liés à l'argent, un seul endroit.
--
-- `playCashSound` — le son de gain. Trois flux le jouent (le claim dans
-- RocketLaunchBehavior, chaque dépôt du compteur dans MoneyDisplay.addVisual, et la
-- récompense journalière) et ils doivent rester identiques : c'est le même feedback
-- "j'ai encaissé" pour le joueur.
--
-- `playBillPop` — le petit "pop" d'un billet qui atterrit dans le compteur pendant
-- l'aspiration (MoneyBurst, §6.21). Joué en rafale, d'où son volume propre.
--
-- `playBigPayout` — le son "gros lot" des paliers de paiement élevés (PayoutTiers,
-- §6.4). Même asset que les flashs de claim, volume propre.
--
-- Chaque son garde un template créé une fois et CLONÉ à chaque lecture : pas de fetch
-- CDN au moment du gain, et deux lectures peuvent se superposer sans se couper.
--
-- `SfxOptions` permet de faire varier une lecture sans toucher au template : c'est ce
-- qui fait monter le son palier après palier (pitch) et chunk après chunk pendant le
-- paiement — la répétition devient un combo au lieu d'un spam.
local function makeSfx(name, config)
	local template = Instance.new("Sound")
	template.Name = name
	template.SoundId = config.id
	template.Volume = config.volume
	template.Parent = SoundService
	return {
		play = function(self, options)
			local sound = template:Clone()
			local _result = options
			if _result ~= nil then
				_result = _result.pitch
			end
			if _result ~= nil then
				sound.PlaybackSpeed = options.pitch
			end
			local _result_1 = options
			if _result_1 ~= nil then
				_result_1 = _result_1.volume
			end
			if _result_1 ~= nil then
				sound.Volume = options.volume
			end
			sound.Parent = SoundService
			sound:Play()
			sound.Ended:Connect(function()
				return sound:Destroy()
			end)
		end,
		preload = function(self)
			task.spawn(function()
				pcall(function()
					return ContentProvider:PreloadAsync({ template })
				end)
			end)
		end,
	}
end
local cash = makeSfx("CashSoundTemplate", AudioConfig.sfx.moneyGain)
local billPop = makeSfx("BillPopSoundTemplate", AudioConfig.sfx.billPop)
local bigPayout = makeSfx("BigPayoutSoundTemplate", AudioConfig.sfx.bigPayout)
local function playCashSound(options)
	cash:play(options)
end
local function playBillPop()
	billPop:play()
end
local function playBigPayout(options)
	bigPayout:play(options)
end
-- Appelé une fois au démarrage du client (RocketLaunchBehavior.init).
local function preloadCashSound()
	cash:preload()
	billPop:preload()
	bigPayout:preload()
end
return {
	playCashSound = playCashSound,
	playBillPop = playBillPop,
	playBigPayout = playBigPayout,
	preloadCashSound = preloadCashSound,
}
