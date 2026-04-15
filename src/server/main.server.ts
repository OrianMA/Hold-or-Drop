import { makeHello } from "shared/module";
import { services } from "./services";

print(makeHello("main.server.ts"));

for (const service of services) {
	service.init();
}