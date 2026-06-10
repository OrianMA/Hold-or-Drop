import { TweenService } from "@rbxts/services";

// ── Configuration ─────────────────────────────────────────────────────────────

// Zone d'apparition aléatoire (coordonnées écran, scale 0–1)
const SPAWN = { xMin: 0.4, xMax: 0.6, yMin: 0.25, yMax: 0.4 };

const FlyTI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
// Pause à taille native avant que le label ne s'envole (pas de bump au spawn).
const HOLD_BEFORE_FLY = 0.17;

// ── Internal ──────────────────────────────────────────────────────────────────

// Clone le template Studio (visuels et taille inchangés) et met à jour le texte.
function build(template: Frame, parent: ScreenGui, delta: number): Frame {
	const frame = template.Clone();
	frame.Name = "FloatingMultiplierLabel";
	frame.AnchorPoint = new Vector2(0.5, 0.5); // requis pour le centrage
	frame.ZIndex = 20;
	frame.Visible = true;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${tostring(math.round(delta * 10) / 10)}`;

	frame.Parent = parent;
	return frame;
}

// ── Public API ────────────────────────────────────────────────────────────────

// Fait apparaître un clone du template à une position aléatoire centrale (à sa
// taille Studio, sans ajustement), marque une courte pause, puis le fait voler
// vers targetLabel. onArrived est appelé à l'impact pour bumper le MultiplierLabel.
export function spawnFloatingMultiplierLabel(
	parent: ScreenGui,
	template: Frame,
	delta: number,
	targetLabel: TextLabel,
	onArrived: () => void,
): void {
	const spawnX = SPAWN.xMin + math.random() * (SPAWN.xMax - SPAWN.xMin);
	const spawnY = SPAWN.yMin + math.random() * (SPAWN.yMax - SPAWN.yMin);

	const frame = build(template, parent, delta);
	frame.Position = new UDim2(spawnX, 0, spawnY, 0);

	task.delay(HOLD_BEFORE_FLY, () => {
		const screenSize = parent.AbsoluteSize;
		if (screenSize.X === 0) {
			frame.Destroy();
			onArrived();
			return;
		}

		// Centre absolu du targetLabel → coordonnées écran (scale)
		const targetCenter = targetLabel.AbsolutePosition.add(targetLabel.AbsoluteSize.div(2));
		const targetPos = new UDim2(targetCenter.X / screenSize.X, 0, targetCenter.Y / screenSize.Y, 0);

		const flyTween = TweenService.Create(frame, FlyTI, { Position: targetPos });
		flyTween.Completed.Connect(() => {
			frame.Destroy();
			onArrived();
		});
		flyTween.Play();
	});
}
