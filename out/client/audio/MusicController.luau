-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Musique client : BGM de base (nouvelle API audio, pour exposer un spectre au visualiser)
-- qui joue en permanence + piste "haute altitude" (Sound classique) crossfadée par-dessus
-- quand la fusée dépasse le seuil d'altitude. SFX restent à leurs call sites.
-- Crossfade BGM de base -> piste haute altitude au passage du seuil.
local CROSSFADE_TO_HIGH = 0.8
-- Coupe rapide de la musique du run au moment de l'explosion (l'explosion est brutale).
local RUN_CUT = 0.25
-- Retour lent de la BGM de base une fois le run terminé.
local BGM_RESUME = 3
-- BGM via la nouvelle API audio : AudioPlayer -> AudioFader -> AudioDeviceOutput (audible)
-- et AudioPlayer -> AudioAnalyzer (analyse spectre, tap AVANT le fader). Le duck agit sur
-- le fader, pas sur le player : la branche audible se coupe mais le spectre reste complet,
-- donc le visualiser continue de tourner pendant le run.
local bgmPlayer
local bgmFader
local bgmAnalyzer
local bgmIndex = 0
local bgmFadeTween
local bgmDucked = false
-- Piste "haute altitude" — Sound classique bouclée, crossfadée par-dessus la BGM de base.
local highTrack
local highTrackFadeTween
local function createSound(id, volume, name, looped)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	return sound
end
local function createWire(source, target, parent)
	local wire = Instance.new("Wire")
	wire.SourceInstance = source
	wire.SourceName = "Output"
	wire.TargetInstance = target
	wire.TargetName = "Input"
	wire.Parent = parent
end
-- Fait fondre le volume audible de la BGM vers une cible (sur le fader, multiplicateur
-- 1 = plein / 0 = muet). Annule tout fade en cours pour qu'un hold -> release rapide ne
-- laisse pas deux tweens se battre sur Volume. Le spectre n'est pas affecté (tap avant le fader).
local function fadeBgm(targetVolume, duration)
	if not bgmFader then
		return nil
	end
	local _result = bgmFadeTween
	if _result ~= nil then
		_result:Cancel()
	end
	bgmFadeTween = TweenService:Create(bgmFader, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = targetVolume,
	})
	bgmFadeTween:Play()
end
-- Fait fondre le volume de la piste haute altitude (Sound classique) vers une cible.
-- Annule tout fade en cours pour éviter deux tweens concurrents sur Volume.
local function fadeHighTrack(targetVolume, duration)
	if not highTrack then
		return nil
	end
	local _result = highTrackFadeTween
	if _result ~= nil then
		_result:Cancel()
	end
	highTrackFadeTween = TweenService:Create(highTrack, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = targetVolume,
	})
	highTrackFadeTween:Play()
end
-- Coupe net la piste haute altitude (annule son fade et la stoppe).
local function stopHighTrack()
	local _result = highTrackFadeTween
	if _result ~= nil then
		_result:Cancel()
	end
	highTrackFadeTween = nil
	local _result_1 = highTrack
	if _result_1 ~= nil then
		_result_1:Stop()
	end
end
-- Fin du run — ramène la BGM de base lentement et s'assure que la piste haute altitude
-- est coupée. No-op sur la BGM si elle n'est pas duckée.
local function resumeBgm()
	stopHighTrack()
	if not bgmDucked then
		return nil
	end
	bgmDucked = false
	fadeBgm(1, BGM_RESUME)
end
local function playBgmTrack(index)
	if not bgmPlayer then
		return nil
	end
	local playlist = AudioConfig.bgm.playlist
	if #playlist == 0 then
		return nil
	end
	bgmIndex = index % #playlist
	local id = playlist[bgmIndex + 1]
	if id == nil then
		return nil
	end
	bgmPlayer.Asset = id
	bgmPlayer:Play()
end
local MusicController = {
	init = function(self)
		-- BGM. Une piste boucle via Looping ; plusieurs pistes avancent sur Ended et
		-- reviennent à la première.
		local playlist = AudioConfig.bgm.playlist
		local firstTrack = playlist[1]
		if firstTrack ~= nil then
			local player = Instance.new("AudioPlayer")
			player.Name = "BGM"
			player.Volume = AudioConfig.bgm.volume
			player.Looping = #playlist == 1
			player.Asset = firstTrack
			player.Parent = SoundService
			local output = Instance.new("AudioDeviceOutput")
			output.Player = Players.LocalPlayer
			output.Parent = player
			-- Fader sur la branche audible uniquement : le duck s'applique ici.
			local fader = Instance.new("AudioFader")
			fader.Name = "BGMFader"
			fader.Parent = player
			local analyzer = Instance.new("AudioAnalyzer")
			analyzer.SpectrumEnabled = true
			analyzer.WindowSize = Enum.AudioWindowSize.Medium
			analyzer.Parent = player
			-- Audible : player -> fader -> output (le fader ducke sans toucher le spectre).
			createWire(player, fader, player)
			createWire(fader, output, player)
			-- Analyse : tap direct sur le player (avant le fader) -> spectre constant.
			createWire(player, analyzer, player)
			bgmPlayer = player
			bgmFader = fader
			bgmAnalyzer = analyzer
			if #playlist > 1 then
				player.Ended:Connect(function()
					return playBgmTrack(bgmIndex + 1)
				end)
			end
			-- Précharge l'asset pour éviter un stall au premier Play.
			task.spawn(function()
				ContentProvider:PreloadAsync({ player })
			end)
			playBgmTrack(0)
		end
		-- Piste haute altitude — créée + préchargée maintenant (pas de stall au 1er crossfade), bouclée.
		highTrack = createSound(AudioConfig.highAltitude.id, AudioConfig.highAltitude.volume, "HighAltitudeMusic", true)
		task.spawn(function()
			return ContentProvider:PreloadAsync({ highTrack })
		end)
		-- Un respawn (typiquement après explosion mortelle) termine le run -> ramène la BGM.
		Players.LocalPlayer.CharacterAdded:Connect(function()
			return resumeBgm()
		end)
	end,
	startRun = function(self)
		stopHighTrack()
		bgmDucked = false
		fadeBgm(1, 0.3)
	end,
	enterHighAltitude = function(self)
		if not highTrack then
			return nil
		end
		fadeBgm(0, CROSSFADE_TO_HIGH)
		bgmDucked = true
		highTrack.Volume = 0
		highTrack.TimePosition = 0
		highTrack:Play()
		fadeHighTrack(AudioConfig.highAltitude.volume, CROSSFADE_TO_HIGH)
	end,
	stopRunMusic = function(self)
		stopHighTrack()
		fadeBgm(0, RUN_CUT)
		bgmDucked = true
	end,
	resumeBgm = resumeBgm,
	getBgmAnalyzer = function(self)
		return bgmAnalyzer
	end,
}
return {
	MusicController = MusicController,
}
