import { ContentProvider, Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Centralised client music: the background playlist (BGM) and the button-hold
// music. Both are non-3D personal sounds parented to SoundService. SFX stay in
// their own call sites (ButtonInGameBehavior / ButtonInGameModule) — this module
// only owns music.

// BGM ducks out fast when a hold starts, then eases back in slowly once the run
// is fully over (respawn after death, or the end of the payout animation).
const BGM_FADE_OUT = 0.4;
const BGM_RESUME = 3;

// BGM — one Sound reused for the whole playlist.
let bgmSound: Sound | undefined;
let bgmIndex = 0;
let bgmFadeTween: Tween | undefined;
let bgmDucked = false;

// Button-hold music — created once, played/stopped on demand.
let buttonMusic: Sound | undefined;

function createSound(id: string, volume: number, name: string, looped: boolean): Sound {
	const sound = new Instance("Sound");
	sound.Name = name;
	sound.SoundId = id;
	sound.Volume = volume;
	sound.Looped = looped;
	sound.Parent = SoundService;
	return sound;
}

// Fade the BGM volume to a target. Cancels any in-flight fade so a quick
// hold → release doesn't leave two tweens fighting over Volume.
function fadeBgm(targetVolume: number, duration: number): void {
	if (!bgmSound) return;
	bgmFadeTween?.Cancel();
	bgmFadeTween = TweenService.Create(
		bgmSound,
		new TweenInfo(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume: targetVolume },
	);
	bgmFadeTween.Play();
}

// End of the run — eases the BGM back in slowly. No-op unless it's currently
// ducked, so spurious respawns/joins don't trigger a pointless fade.
function resumeBgm(): void {
	if (!bgmDucked) return;
	bgmDucked = false;
	fadeBgm(AudioConfig.bgm.volume, BGM_RESUME);
}

function playBgmTrack(index: number): void {
	if (!bgmSound) return;
	const playlist = AudioConfig.bgm.playlist;
	if (playlist.size() === 0) return;
	bgmIndex = index % playlist.size();
	const id = playlist[bgmIndex];
	if (id === undefined) return;
	bgmSound.SoundId = id;
	bgmSound.Play();
}

export const MusicController = {
	init(): void {
		// Background music. A single track loops seamlessly via Looped; several
		// tracks advance on Ended and wrap back to the first.
		const playlist = AudioConfig.bgm.playlist;
		const firstTrack = playlist[0];
		if (firstTrack !== undefined) {
			bgmSound = createSound(firstTrack, AudioConfig.bgm.volume, "BGM", playlist.size() === 1);
			if (playlist.size() > 1) {
				bgmSound.Ended.Connect(() => playBgmTrack(bgmIndex + 1));
			}
			playBgmTrack(0);
		}

		// Button-hold music — created now so it's ready instantly, preloaded off
		// the boot path to avoid a CDN fetch when the first hold starts.
		buttonMusic = createSound(AudioConfig.buttonGame.id, AudioConfig.buttonGame.volume, "ButtonGameMusic", true);
		task.spawn(() => ContentProvider.PreloadAsync([buttonMusic!]));

		// A respawn (typically after a lethal explosion) ends the run → bring the BGM back.
		Players.LocalPlayer.CharacterAdded.Connect(() => resumeBgm());
	},

	// Start of a hold — duck the BGM out and play the looped button music.
	playButtonMusic(): void {
		fadeBgm(0, BGM_FADE_OUT);
		bgmDucked = true;
		if (!buttonMusic) return;
		buttonMusic.TimePosition = 0;
		buttonMusic.Play();
	},

	// Release or explosion — stop the button music only. The BGM stays ducked
	// until the run is fully over (resumeBgm). Idempotent.
	stopButtonMusic(): void {
		buttonMusic?.Stop();
	},

	// End of the run — respawn after death, or end of the payout animation.
	// Eases the BGM back in slowly.
	resumeBgm,
};
