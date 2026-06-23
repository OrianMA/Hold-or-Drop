import { Players } from "@rbxts/services";
import { RankedEntry } from "shared/LeaderboardConfig";
import * as Cfg from "shared/LeaderboardConfig";

// Drives the 3 podium rigs. Avatar (ApplyDescription) only reloads when a slot's
// occupant changes — the costly call, gated on change. ApplyDescription rescales
// the rig to the player's avatar, so the rig is re-seated feet-on-pedestal after
// every swap (target captured from the template at build time). Slot 1 walks,
// 2 & 3 idle. Empty slots are hidden by parenting the rig out (it keeps its parts
// and reappears on the same spot when shown again).

type Slot = {
	rig: Model;
	home: Instance;
	humanoid: Humanoid;
	animator?: Animator;
	animId: string;
	standX: number;
	standZ: number;
	standTopY: number; // target feet (bounding-box bottom) Y = pedestal top
	scale: RigScale; // podium template body scale, re-applied so players match the editor size
	track?: AnimationTrack;
	occupant?: number;
	hidden: boolean;
};

let slots: Slot[] | undefined;

// The template's giant size lives in the Humanoid scale NumberValues, NOT in the
// applied HumanoidDescription (which reads ~1). We capture them and feed them into
// each player's description scale fields so ApplyDescription rebuilds the avatar at
// the editor-authored size.
type RigScale = { height: number; width: number; depth: number; head: number; proportion: number };

function readScale(humanoid: Humanoid): RigScale {
	const read = (name: string, fallback: number): number => {
		const v = humanoid.FindFirstChild(name) as NumberValue | undefined;
		return v !== undefined ? v.Value : fallback;
	};
	return {
		height: read("BodyHeightScale", 1),
		width: read("BodyWidthScale", 1),
		depth: read("BodyDepthScale", 1),
		head: read("HeadScale", 1),
		proportion: read("BodyProportionScale", 0),
	};
}

function buildSlots(podium: Instance): Slot[] | undefined {
	const built: Slot[] = [];
	for (let i = 1; i <= 3; i++) {
		const rig = podium.FindFirstChild(`${Cfg.PODIUM_RIG_PREFIX}${i}`) as Model | undefined;
		if (!rig) return undefined;
		const humanoid = rig.FindFirstChildOfClass("Humanoid");
		if (!humanoid) return undefined;
		const [bbCF, bbSize] = rig.GetBoundingBox();
		built.push({
			rig,
			home: podium,
			humanoid,
			animator: humanoid.FindFirstChildOfClass("Animator"),
			animId: i === 1 ? Cfg.WALK_ANIM_ID : Cfg.IDLE_ANIM_ID,
			standX: bbCF.Position.X,
			standZ: bbCF.Position.Z,
			standTopY: bbCF.Position.Y - bbSize.Y / 2,
			scale: readScale(humanoid),
			hidden: false,
		});
	}
	return built;
}

// Re-seat the rig so its feet rest on the pedestal, centred on the stand point,
// facing -Z. Reads the live bounding box so it is robust to the rescale that
// ApplyDescription performs (and to the template's custom pivot).
function placeOnPedestal(slot: Slot): void {
	const [bbCF, bbSize] = slot.rig.GetBoundingBox();
	const pivot = slot.rig.GetPivot();
	const pivotToCenter = pivot.Position.sub(bbCF.Position);
	const targetCenter = new Vector3(slot.standX, slot.standTopY + bbSize.Y / 2, slot.standZ);
	slot.rig.PivotTo(new CFrame(targetCenter.add(pivotToCenter)));
}

function ensureAnimation(slot: Slot): void {
	const animator = slot.humanoid.FindFirstChildOfClass("Animator");
	if (!animator) return;
	if (slot.animator !== animator) {
		slot.animator = animator; // animator was rebuilt — reload the track
		slot.track = undefined;
	}
	if (!slot.track) {
		const anim = new Instance("Animation");
		anim.AnimationId = slot.animId;
		slot.track = animator.LoadAnimation(anim);
		slot.track.Looped = true;
	}
	if (!slot.track.IsPlaying) slot.track.Play();
}

function getNameplate(slot: Slot): { name: TextLabel; value: TextLabel } | undefined {
	const head = slot.rig.FindFirstChild("Head") as BasePart | undefined;
	if (!head) return undefined;
	let plate = head.FindFirstChild(Cfg.PODIUM_NAMEPLATE) as BillboardGui | undefined;
	if (!plate) {
		plate = new Instance("BillboardGui");
		plate.Name = Cfg.PODIUM_NAMEPLATE;
		plate.Size = new UDim2(0, 200, 0, 64);
		plate.StudsOffset = new Vector3(0, 2.5, 0);
		plate.AlwaysOnTop = true;
		plate.Adornee = head;

		const nameLabel = new Instance("TextLabel");
		nameLabel.Name = Cfg.ROW_NAME;
		nameLabel.Size = new UDim2(1, 0, 0.5, 0);
		nameLabel.BackgroundTransparency = 1;
		nameLabel.TextScaled = true;
		nameLabel.Font = Enum.Font.GothamBold;
		nameLabel.TextColor3 = new Color3(1, 1, 1);
		nameLabel.Parent = plate;

		const valueLabel = new Instance("TextLabel");
		valueLabel.Name = Cfg.ROW_VALUE;
		valueLabel.Position = new UDim2(0, 0, 0.5, 0);
		valueLabel.Size = new UDim2(1, 0, 0.5, 0);
		valueLabel.BackgroundTransparency = 1;
		valueLabel.TextScaled = true;
		valueLabel.Font = Enum.Font.GothamBold;
		valueLabel.TextColor3 = Color3.fromRGB(255, 215, 0);
		valueLabel.Parent = plate;

		plate.Parent = head;
	}
	return {
		name: plate.FindFirstChild(Cfg.ROW_NAME) as TextLabel,
		value: plate.FindFirstChild(Cfg.ROW_VALUE) as TextLabel,
	};
}

function show(slot: Slot): void {
	if (slot.hidden) {
		slot.rig.Parent = slot.home;
		slot.hidden = false;
	}
}

function hide(slot: Slot): void {
	if (!slot.hidden) {
		slot.rig.Parent = undefined;
		slot.hidden = true;
	}
	slot.occupant = undefined;
}

function applyAvatar(slot: Slot, userId: number): void {
	// On a transient fetch/apply failure we DON'T record the occupant, so the next
	// refresh retries instead of leaving the rig stuck on the template appearance.
	const [ok, descRaw] = pcall(() => Players.GetHumanoidDescriptionFromUserId(userId));
	if (!ok) return;
	// Keep the player's appearance but force the podium template's body scale so the
	// rig matches the size authored in the editor (ApplyDescription drives the avatar
	// size from these scale fields).
	const desc = descRaw as HumanoidDescription;
	desc.HeightScale = slot.scale.height;
	desc.WidthScale = slot.scale.width;
	desc.DepthScale = slot.scale.depth;
	desc.HeadScale = slot.scale.head;
	desc.ProportionScale = slot.scale.proportion;
	const [applied] = pcall(() => slot.humanoid.ApplyDescription(desc));
	if (!applied) return;
	// Re-anchor the root and re-seat the (now editor-sized) rig on the pedestal.
	const root = slot.rig.FindFirstChild("HumanoidRootPart") as BasePart | undefined;
	if (root) root.Anchored = true;
	placeOnPedestal(slot);
	slot.occupant = userId;
}

export function renderPodium(podium: Instance, top3: RankedEntry[], format: (v: number) => string): void {
	if (!slots) slots = buildSlots(podium);
	if (!slots) return;
	for (let i = 0; i < 3; i++) {
		const slot = slots[i];
		const entry = top3[i];
		if (!entry) {
			hide(slot);
			continue;
		}
		show(slot);
		if (slot.occupant !== entry.userId) applyAvatar(slot, entry.userId);
		const plate = getNameplate(slot);
		if (plate) {
			plate.name.Text = entry.name;
			plate.value.Text = format(entry.value);
		}
		ensureAnimation(slot);
	}
}
