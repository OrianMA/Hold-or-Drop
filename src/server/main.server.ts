import { services } from "./services/index";

for (const service of services) {
	service.init();
}
