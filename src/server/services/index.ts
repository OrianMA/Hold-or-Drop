import { ButtonTriggerService } from "./ButtonTriggerService";
import { UiService } from "./UiService";
import { PopupConfig } from "server/UI/PopupConfig";

export const services: Array<{ init(): void }> = [
	{
		init() {
			UiService.init(PopupConfig);
		},
	},
	ButtonTriggerService,
];
