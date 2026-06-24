import { ContentProvider, Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Musique client : BGM (nouvelle API audio, pour exposer un spectre au visualiser) +
// musique du bouton (Sound classique, inchangée). SFX restent à leurs call sites.

// La BGM ducke vite au début d'un hold puis revient lentement une fois le run terminé.
const BGM_FADE_OUT = 0.4;
const BGM_RESUME = 3;

// BGM via la nouvelle API audio : AudioPlayer -> AudioFader -> AudioDeviceOutput (audible)
// et AudioPlayer -> AudioAnalyzer (analyse spectre, tap AVANT le fader). Le duck agit sur
// le fader, pas sur le player : la branche audible se coupe mais le spectre reste complet,
// donc le visualiser continue de tourner pendant le run.
let bgmPlayer: AudioPlayer | undefined;
let bgmFader: AudioFader | undefined;
let bgmAnalyzer: AudioAnalyzer | undefined;
let bgmIndex = 0;
let bgmFadeTween: Tween | undefined;
let bgmDucked = false;

// Musique du bouton — Sound classique, créée/jouée à la demande.
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

function createWire(source: Instance, target: Instance, parent: Instance): void {
	const wire = new Instance("Wire");
	wire.SourceInstance = source;
	wire.SourceName = "Output";
	wire.TargetInstance = target;
	wire.TargetName = "Input";
	wire.Parent = parent;
}

// Fait fondre le volume audible de la BGM vers une cible (sur le fader, multiplicateur
// 1 = plein / 0 = muet). Annule tout fade en cours pour qu'un hold -> release rapide ne
// laisse pas deux tweens se battre sur Volume. Le spectre n'est pas affecté (tap avant le fader).
function fadeBgm(targetVolume: number, duration: number): void {
	if (!bgmFader) return;
	bgmFadeTween?.Cancel();
	bgmFadeTween = TweenService.Create(
		bgmFader,
		new TweenInfo(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume: targetVolume },
	);
	bgmFadeTween.Play();
}

// Fin du run — ramène la BGM lentement. No-op si elle n'est pas duckée.
function resumeBgm(): void {
	if (!bgmDucked) return;
	bgmDucked = false;
	fadeBgm(1, BGM_RESUME);
}

function playBgmTrack(index: number): void {
	if (!bgmPlayer) return;
	const playlist = AudioConfig.bgm.playlist;
	if (playlist.size() === 0) return;
	bgmIndex = index % playlist.size();
	const id = playlist[bgmIndex];
	if (id === undefined) return;
	bgmPlayer.Asset = id;
	bgmPlayer.Play();
}

export const MusicController = {
	init(): void {
		// BGM. Une piste boucle via Looping ; plusieurs pistes avancent sur Ended et
		// reviennent à la première.
		const playlist = AudioConfig.bgm.playlist;
		const firstTrack = playlist[0];
		if (firstTrack !== undefined) {
			const player = new Instance("AudioPlayer");
			player.Name = "BGM";
			player.Volume = AudioConfig.bgm.volume;
			player.Looping = playlist.size() === 1;
			player.Asset = firstTrack;
			player.Parent = SoundService;

			const output = new Instance("AudioDeviceOutput");
			output.Player = Players.LocalPlayer;
			output.Parent = player;

			// Fader sur la branche audible uniquement : le duck s'applique ici.
			const fader = new Instance("AudioFader");
			fader.Name = "BGMFader";
			fader.Parent = player;

			const analyzer = new Instance("AudioAnalyzer");
			analyzer.SpectrumEnabled = true;
			analyzer.WindowSize = Enum.AudioWindowSize.Medium;
			analyzer.Parent = player;

			// Audible : player -> fader -> output (le fader ducke sans toucher le spectre).
			createWire(player, fader, player);
			createWire(fader, output, player);
			// Analyse : tap direct sur le player (avant le fader) -> spectre constant.
			createWire(player, analyzer, player);

			bgmPlayer = player;
			bgmFader = fader;
			bgmAnalyzer = analyzer;

			if (playlist.size() > 1) {
				player.Ended.Connect(() => playBgmTrack(bgmIndex + 1));
			}

			// Précharge l'asset pour éviter un stall au premier Play.
			task.spawn(() => {
				ContentProvider.PreloadAsync([player]);
			});
			playBgmTrack(0);
		}

		// Musique du bouton — créée + préchargée maintenant (pas de stall au 1er hold), bouclée.
		buttonMusic = createSound(AudioConfig.buttonGame.id, AudioConfig.buttonGame.volume, "ButtonGameMusic", true);
		task.spawn(() => ContentProvider.PreloadAsync([buttonMusic!]));

		// Un respawn (typiquement après explosion mortelle) termine le run -> ramène la BGM.
		Players.LocalPlayer.CharacterAdded.Connect(() => resumeBgm());
	},

	// Début d'un hold — ducke la BGM et joue la musique de bouton bouclée.
	playButtonMusic(): void {
		fadeBgm(0, BGM_FADE_OUT);
		bgmDucked = true;
		if (!buttonMusic) return;
		buttonMusic.TimePosition = 0;
		buttonMusic.Play();
	},

	// Release ou explosion — stoppe seulement la musique de bouton. Idempotent.
	stopButtonMusic(): void {
		buttonMusic?.Stop();
	},

	// Fin du run — respawn après mort, ou fin de l'animation de payout.
	resumeBgm,

	// Permet au visualiser de lire le spectre de la BGM (client uniquement).
	getBgmAnalyzer(): AudioAnalyzer | undefined {
		return bgmAnalyzer;
	},
};
