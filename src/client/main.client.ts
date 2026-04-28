import { Events } from "shared/Event";
import { CameraController } from "shared/CameraController";

Events.ButtonTriggerEvent.OnClientEvent.Connect((cameraPosPart: BasePart) => {
	CameraController.SetCinematic();
	CameraController.AnimateTo(cameraPosPart.CFrame);
});
