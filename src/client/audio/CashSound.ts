import { ContentProvider, SoundService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Les sons 2D liés à l'argent, un seul endroit.
//
// `playCashSound` — le son de gain. Trois flux le jouent (le claim dans
// RocketLaunchBehavior, chaque dépôt du compteur dans MoneyDisplay.addVisual, et la
// récompense journalière) et ils doivent rester identiques : c'est le même feedback
// "j'ai encaissé" pour le joueur.
//
// `playBillPop` — le petit "pop" d'un billet qui atterrit dans le compteur pendant
// l'aspiration (MoneyBurst, §6.21). Joué en rafale, d'où son volume propre.
//
// Chaque son garde un template créé une fois et CLONÉ à chaque lecture : pas de fetch
// CDN au moment du gain, et deux lectures peuvent se superposer sans se couper.

interface SoundConfig {
	readonly id: string;
	readonly volume: number;
}

function makeSfx(name: string, config: SoundConfig) {
	const template = new Instance("Sound");
	template.Name = name;
	template.SoundId = config.id;
	template.Volume = config.volume;
	template.Parent = SoundService;

	return {
		play(): void {
			const sound = template.Clone();
			sound.Parent = SoundService;
			sound.Play();
			sound.Ended.Connect(() => sound.Destroy());
		},
		// Met le son en cache pour que la TOUTE première lecture de la session soit
		// instantanée (les suivantes réutilisent le cache).
		preload(): void {
			task.spawn(() => {
				pcall(() => ContentProvider.PreloadAsync([template]));
			});
		},
	};
}

const cash = makeSfx("CashSoundTemplate", AudioConfig.sfx.moneyGain);
const billPop = makeSfx("BillPopSoundTemplate", AudioConfig.sfx.billPop);

export function playCashSound(): void {
	cash.play();
}

export function playBillPop(): void {
	billPop.play();
}

// Appelé une fois au démarrage du client (RocketLaunchBehavior.init).
export function preloadCashSound(): void {
	cash.preload();
	billPop.preload();
}
