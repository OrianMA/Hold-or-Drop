-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Musique client : BGM (nouvelle API audio, pour exposer un spectre au visualiser) +
-- musique du bouton (Sound classique, inchangée). SFX restent à leurs call sites.
-- La BGM ducke vite au début d'un hold puis revient lentement une fois le run terminé.
local BGM_FADE_OUT = 0.4
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
-- Musique du bouton — Sound classique, créée/jouée à la demande.
local buttonMusic
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
-- Fin du run — ramène la BGM lentement. No-op si elle n'est pas duckée.
local function resumeBgm()
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
		-- Musique du bouton — créée + préchargée maintenant (pas de stall au 1er hold), bouclée.
		buttonMusic = createSound(AudioConfig.buttonGame.id, AudioConfig.buttonGame.volume, "ButtonGameMusic", true)
		task.spawn(function()
			return ContentProvider:PreloadAsync({ buttonMusic })
		end)
		-- Un respawn (typiquement après explosion mortelle) termine le run -> ramène la BGM.
		Players.LocalPlayer.CharacterAdded:Connect(function()
			return resumeBgm()
		end)
	end,
	playButtonMusic = function(self)
		fadeBgm(0, BGM_FADE_OUT)
		bgmDucked = true
		if not buttonMusic then
			return nil
		end
		buttonMusic.TimePosition = 0
		buttonMusic:Play()
	end,
	stopButtonMusic = function(self)
		local _result = buttonMusic
		if _result ~= nil then
			_result:Stop()
		end
	end,
	resumeBgm = resumeBgm,
	getBgmAnalyzer = function(self)
		return bgmAnalyzer
	end,
}
return {
	MusicController = MusicController,
}
