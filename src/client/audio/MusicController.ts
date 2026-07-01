import { ContentProvider, Players, SoundService, TweenService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Musique client : BGM de base (nouvelle API audio, pour exposer un spectre au visualiser)
// qui joue en permanence + piste "haute altitude" (Sound classique) crossfadée par-dessus
// quand la fusée dépasse le seuil d'altitude. SFX restent à leurs call sites.

// Crossfade BGM de base -> piste haute altitude au passage du seuil.
const CROSSFADE_TO_HIGH = 0.8;
// Coupe rapide de la musique du run au moment de l'explosion (l'explosion est brutale).
const RUN_CUT = 0.25;
// Retour lent de la BGM de base une fois le run terminé.
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

// Piste "haute altitude" — Sound classique bouclée, crossfadée par-dessus la BGM de base.
let highTrack: Sound | undefined;
let highTrackFadeTween: Tween | undefined;

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

// Fait fondre le volume de la piste haute altitude (Sound classique) vers une cible.
// Annule tout fade en cours pour éviter deux tweens concurrents sur Volume.
function fadeHighTrack(targetVolume: number, duration: number): void {
	if (!highTrack) return;
	highTrackFadeTween?.Cancel();
	highTrackFadeTween = TweenService.Create(
		highTrack,
		new TweenInfo(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume: targetVolume },
	);
	highTrackFadeTween.Play();
}

// Coupe net la piste haute altitude (annule son fade et la stoppe).
function stopHighTrack(): void {
	highTrackFadeTween?.Cancel();
	highTrackFadeTween = undefined;
	highTrack?.Stop();
}

// Fin du run — ramène la BGM de base lentement et s'assure que la piste haute altitude
// est coupée. No-op sur la BGM si elle n'est pas duckée.
function resumeBgm(): void {
	stopHighTrack();
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

		// Piste haute altitude — créée + préchargée maintenant (pas de stall au 1er crossfade), bouclée.
		highTrack = createSound(AudioConfig.highAltitude.id, AudioConfig.highAltitude.volume, "HighAltitudeMusic", true);
		task.spawn(() => ContentProvider.PreloadAsync([highTrack!]));

		// Un respawn (typiquement après explosion mortelle) termine le run -> ramène la BGM.
		Players.LocalPlayer.CharacterAdded.Connect(() => resumeBgm());
	},

	// Début d'un hold — la fusée est sur le pad, sous le seuil : on garde la BGM de base.
	// On s'assure juste que la piste haute altitude est coupée et la BGM à plein volume
	// (au cas où une coupe d'explosion précédente l'aurait laissée duckée).
	startRun(): void {
		stopHighTrack();
		bgmDucked = false;
		fadeBgm(1, 0.3);
	},

	// La fusée dépasse le seuil d'altitude — crossfade BGM de base -> piste haute altitude.
	enterHighAltitude(): void {
		if (!highTrack) return;
		fadeBgm(0, CROSSFADE_TO_HIGH);
		bgmDucked = true;
		highTrack.Volume = 0;
		highTrack.TimePosition = 0;
		highTrack.Play();
		fadeHighTrack(AudioConfig.highAltitude.volume, CROSSFADE_TO_HIGH);
	},

	// Explosion / fin du run — coupe la piste haute altitude et ducke la BGM de base pour
	// finir sur du silence. resumeBgm la ramènera au retour sur le joueur. Idempotent.
	stopRunMusic(): void {
		stopHighTrack();
		fadeBgm(0, RUN_CUT);
		bgmDucked = true;
	},

	// Fin du run — respawn après mort, ou fin de l'animation de payout.
	resumeBgm,

	// Permet au visualiser de lire le spectre de la BGM (client uniquement).
	getBgmAnalyzer(): AudioAnalyzer | undefined {
		return bgmAnalyzer;
	},
};
