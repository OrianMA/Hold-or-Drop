import { Players, SoundService } from "@rbxts/services";
import { AudioConfig } from "shared/AudioConfig";

// Son de clic centralisé pour TOUTE l'UI. Au lieu de câbler le son bouton par
// bouton, on accroche automatiquement chaque GuiButton du PlayerGui : ceux déjà
// présents au démarrage et ceux ajoutés plus tard (DescendantAdded). Ainsi tout
// nouveau bouton créé en Studio joue ce son sans aucune ligne de code en plus.
//
// 100 % client / présentation. Son 2D (personnel), joué via un template
// préchargé en SoundService — cloné à chaque clic pour autoriser les
// chevauchements et éviter un fetch CDN au premier clic.

const CLICK_ID = AudioConfig.sfx.uiClick.id;
const CLICK_VOLUME = AudioConfig.sfx.uiClick.volume;

// Template persistant : garde l'asset en mémoire dès le démarrage.
const template = (() => {
	const sound = new Instance("Sound");
	sound.Name = "UiClickTemplate";
	sound.SoundId = CLICK_ID;
	sound.Volume = CLICK_VOLUME;
	sound.Parent = SoundService;
	return sound;
})();

function playClick(): void {
	const sound = template.Clone();
	sound.Parent = SoundService;
	sound.Play();
	sound.Ended.Connect(() => sound.Destroy());
}

// Évite de connecter deux fois le même bouton (le scan initial et DescendantAdded
// peuvent se recouper selon l'ordre de chargement du PlayerGui).
const hooked = new Set<GuiButton>();

function hook(instance: Instance): void {
	if (!instance.IsA("GuiButton")) return;
	if (hooked.has(instance)) return;
	hooked.add(instance);
	instance.Activated.Connect(playClick);
}

export function init(): void {
	const gui = Players.LocalPlayer.WaitForChild("PlayerGui");

	for (const desc of gui.GetDescendants()) hook(desc);
	gui.DescendantAdded.Connect(hook);
}
