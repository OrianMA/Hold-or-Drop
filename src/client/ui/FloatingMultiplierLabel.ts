import { TweenService } from "@rbxts/services";

// ── Configuration ─────────────────────────────────────────────────────────────

// Zone d'apparition aléatoire (coordonnées écran, scale 0–1)
const SPAWN = { xMin: 0.4, xMax: 0.6, yMin: 0.25, yMax: 0.4 };

const BumpInTI = new TweenInfo(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
const BumpOutTI = new TweenInfo(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
const FlyTI = new TweenInfo(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In);

// ── Internal ──────────────────────────────────────────────────────────────────

// Clone le template Studio (visuels inchangés), met à jour le texte,
// et ajoute uniquement le UIScale nécessaire pour l'animation bump.
function build(template: Frame, parent: ScreenGui, delta: number): [Frame, UIScale] {
	const frame = template.Clone();
	frame.Name = "FloatingMultiplierLabel";
	frame.AnchorPoint = new Vector2(0.5, 0.5); // requis pour le centrage et le bump
	frame.ZIndex = 20;
	frame.Visible = true;

	const amountLabel = frame.FindFirstChild("Amount") as TextLabel | undefined;
	if (amountLabel) amountLabel.Text = `+${delta}`;

	// UIScale sur l'icône uniquement — la frame et le texte gardent leur taille Studio
	const icon = frame.FindFirstChild("Icon") as ImageLabel | undefined;
	const uiScale = new Instance("UIScale");
	uiScale.Scale = 0.9;
	uiScale.Parent = icon ?? frame; // fallback sur la frame si pas d'enfant "Icon"

	frame.Parent = parent;
	return [frame, uiScale];
}

// ── Public API ────────────────────────────────────────────────────────────────

// Fait apparaître un clone du template à une position aléatoire centrale,
// le fait bumper (0.9 → 1.1 → 1.0), puis voler vers targetLabel.
// onArrived est appelé à l'impact pour déclencher le bump du MultiplierLabel.
export function spawnFloatingMultiplierLabel(
	parent: ScreenGui,
	template: Frame,
	delta: number,
	targetLabel: TextLabel,
	onArrived: () => void,
): void {
	const spawnX = SPAWN.xMin + math.random() * (SPAWN.xMax - SPAWN.xMin);
	const spawnY = SPAWN.yMin + math.random() * (SPAWN.yMax - SPAWN.yMin);

	const [frame, uiScale] = build(template, parent, delta);
	frame.Position = new UDim2(spawnX, 0, spawnY, 0);

	// Bump in : 0.9 → 1.1
	TweenService.Create(uiScale, BumpInTI, { Scale: 1.1 }).Play();

	task.delay(BumpInTI.Time, () => {
		// Settle : 1.1 → 1.0
		TweenService.Create(uiScale, BumpOutTI, { Scale: 1.0 }).Play();

		task.delay(BumpOutTI.Time + 0.04, () => {
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
	});
}
