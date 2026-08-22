import { Players, Workspace } from "@rbxts/services";
import { Events } from "shared/Event";
import { RoomService } from "server/rooms/RoomService";
import { megaRocketCheatDelay, megaRocketCheatKey, megaRocketInterval } from "server/modules/CheatConfig";
import { RocketLauncher } from "server/modules/RocketLauncher";
import { RocketPlacer } from "server/modules/RocketPlacer";
import {
	MEGA_ROCKET_ANNOUNCE,
	MEGA_ROCKET_ATTR,
	MEGA_ROCKET_INTERVAL,
	MEGA_ROCKET_PANEL_FIRED,
	megaRocketPanelText,
} from "shared/MegaRocketConfig";

// Horloge de l'événement Mega Rocket (§6.24). Une seule boucle serveur pour tout
// le serveur : elle écrit le compte à rebours sur le panneau de l'Environment et,
// toutes les MEGA_ROCKET_INTERVAL secondes, donne sa Mega Rocket à chaque joueur.
//
// Au top de l'événement :
//   • tout le monde reçoit l'attribut MegaRocket ;
//   • les fusées encore AU SOL sont reposées tout de suite en version mega ;
//   • celles DÉJÀ EN VOL ne sont pas touchées — leur run en cours reste normal et
//     c'est la fusée suivante qui sera mega (RocketPlacer la repose en fin de vol,
//     l'attribut étant toujours posé).
//
// Le panneau est écrit côté serveur : c'est une TextLabel de Workspace, elle se
// réplique donc telle quelle à tout le monde — pas de RemoteEvent, pas de contrôleur
// client à synchroniser.

const PANEL_PART = "DisplayEventPanel";
const PANEL_LABEL = "EventText";
// Temps pendant lequel le panneau affiche « MEGA ROCKET ! » avant de repartir en
// compte à rebours.
const FIRED_TEXT_DURATION = 5;

// Intervalle réel entre deux événements — raccourcissable pour les tests
// (CheatConfig.megaRocketInterval).
const INTERVAL = megaRocketInterval ?? MEGA_ROCKET_INTERVAL;

// Instant (os.clock) du prochain événement.
let nextEventAt = 0;
// Tant que cet instant n'est pas passé, la boucle laisse « MEGA ROCKET ! » sur le
// panneau au lieu d'y réécrire le compte à rebours. C'est ce qui permet de déclencher
// l'événement DEPUIS L'EXTÉRIEUR de la boucle (achat ScrollToken, §6.27) sans que la
// seconde suivante n'efface le message.
let panelHoldUntil = 0;

function findPanelLabel(): TextLabel | undefined {
	const environment = Workspace.FindFirstChild("Environment");
	const panel = environment?.FindFirstChild(PANEL_PART);
	const gui = panel?.FindFirstChildOfClass("SurfaceGui");
	// Recherche RÉCURSIVE : le label vit sous un Frame de fond (MegaRocketFrame) et
	// peut être ré-emboîté en Studio sans casser le code.
	const label = gui?.FindFirstChild(PANEL_LABEL, true);
	return label !== undefined && label.IsA("TextLabel") ? label : undefined;
}

function setPanelText(text: string): void {
	const label = findPanelLabel();
	if (label) label.Text = text;
}

// Top de l'événement : tout le monde gagne sa Mega Rocket.
// `announce` remplace le bandeau par défaut — un déclenchement acheté annonce QUI l'a
// payé plutôt que le message d'horloge.
function fireEvent(announce = MEGA_ROCKET_ANNOUNCE): void {
	for (const player of Players.GetPlayers()) player.SetAttribute(MEGA_ROCKET_ATTR, true);

	// Bandeau légendaire pour tout le serveur (§6.20).
	Events.InformationTextEvent.FireAllClients(announce, { rarity: "Legendary" });

	// Fusées au sol → elles deviennent mega immédiatement. Un rig qui n'est pas sur
	// son pad (vol en cours, explosion, retour "Go Home" en attente) n'est JAMAIS
	// touché : c'est son replacement de fin de vol qui posera la mega.
	for (const room of RoomService.getRooms()) {
		if (!room.getOccupant()) continue;
		if (!RocketLauncher.isAtPad(room)) continue;
		RocketPlacer.place(room);
	}
}

export const MegaRocketService = {
	init(): void {
		nextEventAt = os.clock() + INTERVAL;
		setPanelText(megaRocketPanelText(INTERVAL));

		// Cheat de dev : la touche G du client ramène le compte à rebours à
		// `megaRocketCheatDelay` secondes (voir CheatConfig / client/MegaRocketCheat).
		// L'event n'est même pas branché quand le cheat est éteint. Seule la prochaine
		// échéance bouge : l'événement d'après repart sur l'intervalle normal.
		if (megaRocketCheatKey) {
			Events.MegaRocketCheatEvent.OnServerEvent.Connect(() => {
				nextEventAt = os.clock() + megaRocketCheatDelay;
				setPanelText(megaRocketPanelText(megaRocketCheatDelay));
			});
		}

		task.spawn(() => {
			while (true) {
				task.wait(1);

				// Un déclenchement acheté vient d'écrire « MEGA ROCKET ! » : on ne touche
				// pas au panneau tant que son temps d'affichage n'est pas écoulé.
				if (os.clock() < panelHoldUntil) continue;

				if (os.clock() >= nextEventAt) {
					// `nextEventAt` est absolu : l'affichage de « MEGA ROCKET ! » ci-dessous
					// ne décale donc pas la cadence de l'événement suivant.
					nextEventAt = os.clock() + INTERVAL;
					fireEvent();
					setPanelText(MEGA_ROCKET_PANEL_FIRED);
					task.wait(FIRED_TEXT_DURATION);
					continue;
				}

				setPanelText(megaRocketPanelText(nextEventAt - os.clock()));
			}
		});
	},

	// Déclenche l'événement TOUT DE SUITE, hors horloge — utilisé par l'achat en
	// ScrollToken (§6.27). La cadence normale REPART de maintenant : sans ça, un achat
	// juste avant l'échéance donnerait deux Mega Rockets à quelques secondes d'écart.
	fireNow(announce: string): void {
		nextEventAt = os.clock() + INTERVAL;
		fireEvent(announce);
		setPanelText(MEGA_ROCKET_PANEL_FIRED);
		panelHoldUntil = os.clock() + FIRED_TEXT_DURATION;
	},

	// La Mega Rocket vient d'être utilisée (le vol qui la portait est terminé) :
	// la prochaine fusée posée sur le pad sera une fusée normale. Appelé par
	// ButtonInGameModule au moment où il repose une fusée neuve.
	consume(player: Player): void {
		player.SetAttribute(MEGA_ROCKET_ATTR, false);
	},
};
