import { services } from "./services/index";

print("Main.server init")

for (const service of services) {
	service.init();
}
