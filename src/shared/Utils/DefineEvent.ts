import { RunService } from "@rbxts/services";

export default function DefineEvent(event_name: string, parent: Instance) {
	if (RunService.IsClient()) {
		return parent.WaitForChild(event_name) as RemoteEvent;
	}

	const event = new Instance("RemoteEvent", parent);
	event.Name = event_name;
	return event;
}
