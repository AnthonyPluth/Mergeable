import { it, expect } from "vitest";
import { registerDevice, listDevices, removeDevice } from "../src/devices";
import { kv } from "./helpers";
it("register, list, remove", async () => {
  const k = kv();
  await registerDevice(k, { token: "a", platform: "ios", environment: "sandbox" });
  expect(await listDevices(k)).toEqual([{ token: "a", platform: "ios", environment: "sandbox" }]);
  await removeDevice(k, "a");
  expect(await listDevices(k)).toEqual([]);
});
