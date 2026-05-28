// Enables the Confetti ParticleEmitters under a button model for 2s then
// disables them. The Confetti folder may contain either ParticleEmitters
// directly or Attachments holding them — both are handled.

const DEFAULT_DURATION = 2;

function collectEmitters(confettiContainer: Instance): ParticleEmitter[] {
	const emitters: ParticleEmitter[] = [];
	for (const child of confettiContainer.GetDescendants()) {
		if (child.IsA("ParticleEmitter")) emitters.push(child);
	}
	return emitters;
}

export const ConfettiBurst = {
	play(buttonModel: Instance | undefined, duration = DEFAULT_DURATION): void {
		if (!buttonModel) return;
		const container = buttonModel.FindFirstChild("Confetti");
		if (!container) return;

		const emitters = collectEmitters(container);
		if (emitters.size() === 0) return;

		for (const emitter of emitters) emitter.Enabled = true;

		task.delay(duration, () => {
			for (const emitter of emitters) {
				if (emitter.Parent === undefined) continue;
				emitter.Enabled = false;
			}
		});
	},
};
