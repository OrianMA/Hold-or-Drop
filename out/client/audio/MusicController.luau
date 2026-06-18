-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local ContentProvider = _services.ContentProvider
local Players = _services.Players
local SoundService = _services.SoundService
local TweenService = _services.TweenService
local AudioConfig = TS.import(script, game:GetService("ReplicatedStorage"), "TS", "AudioConfig").AudioConfig
-- Centralised client music: the background playlist (BGM) and the button-hold
-- music. Both are non-3D personal sounds parented to SoundService. SFX stay in
-- their own call sites (ButtonInGameBehavior / ButtonInGameModule) — this module
-- only owns music.
-- BGM ducks out fast when a hold starts, then eases back in slowly once the run
-- is fully over (respawn after death, or the end of the payout animation).
local BGM_FADE_OUT = 0.4
local BGM_RESUME = 3
-- BGM — one Sound reused for the whole playlist.
local bgmSound
local bgmIndex = 0
local bgmFadeTween
local bgmDucked = false
-- Button-hold music — created once, played/stopped on demand.
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
-- Fade the BGM volume to a target. Cancels any in-flight fade so a quick
-- hold → release doesn't leave two tweens fighting over Volume.
local function fadeBgm(targetVolume, duration)
	if not bgmSound then
		return nil
	end
	local _result = bgmFadeTween
	if _result ~= nil then
		_result:Cancel()
	end
	bgmFadeTween = TweenService:Create(bgmSound, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = targetVolume,
	})
	bgmFadeTween:Play()
end
-- End of the run — eases the BGM back in slowly. No-op unless it's currently
-- ducked, so spurious respawns/joins don't trigger a pointless fade.
local function resumeBgm()
	if not bgmDucked then
		return nil
	end
	bgmDucked = false
	fadeBgm(AudioConfig.bgm.volume, BGM_RESUME)
end
local function playBgmTrack(index)
	if not bgmSound then
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
	bgmSound.SoundId = id
	bgmSound:Play()
end
local MusicController = {
	init = function(self)
		-- Background music. A single track loops seamlessly via Looped; several
		-- tracks advance on Ended and wrap back to the first.
		local playlist = AudioConfig.bgm.playlist
		local firstTrack = playlist[1]
		if firstTrack ~= nil then
			bgmSound = createSound(firstTrack, AudioConfig.bgm.volume, "BGM", #playlist == 1)
			if #playlist > 1 then
				bgmSound.Ended:Connect(function()
					return playBgmTrack(bgmIndex + 1)
				end)
			end
			playBgmTrack(0)
		end
		-- Button-hold music — created now so it's ready instantly, preloaded off
		-- the boot path to avoid a CDN fetch when the first hold starts.
		buttonMusic = createSound(AudioConfig.buttonGame.id, AudioConfig.buttonGame.volume, "ButtonGameMusic", true)
		task.spawn(function()
			return ContentProvider:PreloadAsync({ buttonMusic })
		end)
		-- A respawn (typically after a lethal explosion) ends the run → bring the BGM back.
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
}
return {
	MusicController = MusicController,
}
