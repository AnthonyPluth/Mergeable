import { describe, it, expect, vi } from "vitest";
import worker from "../src/index";
import { kv, hmacHeader } from "./helpers";
import { listDevices } from "../src/devices";

const env = () => ({ MERGEABLE: kv(), WEBHOOK_SECRET: "w", REGISTRATION_SECRET: "r" }) as any;
const ctx = () => ({ waitUntil: vi.fn() }) as any;
const dev = { token: "t", platform: "ios", environment: "production" };
const post = (path: string, body: string, headers: Record<string, string> = {}) => new Request(`https://x${path}`, { method: "POST", body, headers });

describe("routes", () => {
  it("health", async () => expect(await (await worker.fetch(new Request("https://x/health"), env(), ctx())).text()).toBe("ok"));
  it("404", async () => expect((await worker.fetch(new Request("https://x/nope"), env(), ctx())).status).toBe(404));
  it("register/remove with bearer", async () => {
    const e = env();
    expect((await worker.fetch(post("/devices", JSON.stringify(dev), { authorization: "Bearer r" }), e, ctx())).status).toBe(204);
    expect(await listDevices(e.MERGEABLE)).toHaveLength(1);
    expect((await worker.fetch(new Request("https://x/devices/t", { method: "DELETE", headers: { authorization: "Bearer r" } }), e, ctx())).status).toBe(204);
    expect(await listDevices(e.MERGEABLE)).toHaveLength(0);
  });
  it("wrong bearer 401", async () => expect((await worker.fetch(post("/devices", JSON.stringify(dev), { authorization: "Bearer x" }), env(), ctx())).status).toBe(401));
  it("bad json / bad platform 400", async () => {
    const h = { authorization: "Bearer r" };
    expect((await worker.fetch(post("/devices", "{", h), env(), ctx())).status).toBe(400);
    expect((await worker.fetch(post("/devices", JSON.stringify({ ...dev, platform: "tv" }), h), env(), ctx())).status).toBe(400);
    expect((await worker.fetch(post("/devices", JSON.stringify({ ...dev, environment: "x" }), h), env(), ctx())).status).toBe(400);
  });
  it("webhook: bad sig 401, good sig 202 + waitUntil", async () => {
    const c = ctx();
    expect((await worker.fetch(post("/webhook", "{}", { "x-hub-signature-256": "sha256=" + "0".repeat(64) }), env(), c)).status).toBe(401);
    const r = await worker.fetch(post("/webhook", "{}", { "x-hub-signature-256": await hmacHeader("w", "{}"), "x-github-event": "ping" }), env(), c);
    expect(r.status).toBe(202);
    expect(c.waitUntil).toHaveBeenCalled();
  });
});
