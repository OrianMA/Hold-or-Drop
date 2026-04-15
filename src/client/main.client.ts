import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";

Events.InteractionCameraEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
	print(cameraPosPart.Name);
	CameraController.SetCinematic();
	CameraController.AnimateTo(cameraPosPart.CFrame);
});
