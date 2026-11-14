import { describe, it, expect, vi, afterEach } from "vitest";
import { handleWebhook } from "../src/handle";
import { registerDevice, listDevices } from "../src/devices";
import { kv, p256Pem, rsaPem } from "./helpers";
afterEach(() => vi.unstubAllGlobals());

async function setup(prOver: any = {}, pushStatus: (url: string) => number = () => 200) {
  const rsa = await rsaPem(), ec = await p256Pem();
  const env: any = { MERGEABLE: kv(), NOTIFIER_APP_ID: "1", NOTIFIER_PRIVATE_KEY: rsa.pem, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_PRIVATE_KEY: ec.pem, SELF_LOGIN: "AnthonyPluth" };
  await registerDevice(env.MERGEABLE, { token: "prod", platform: "ios", environment: "production" });
  await registerDevice(env.MERGEABLE, { token: "sbx", platform: "macos", environment: "sandbox" });
  const pr = { title: "T", url: "https://github.com/o/r/pull/3", state: "OPEN", isDraft: false, mergeable: "MERGEABLE", headRefOid: "h1", author: { login: "AnthonyPluth" }, commits: { nodes: [{ commit: { statusCheckRollup: { state: "SUCCESS" } } }] }, ...prOver };
  const pushes: { url: string; body: any }[] = [];
  vi.stubGlobal("fetch", async (url: string, init?: RequestInit) => {
    if (url.includes("access_tokens")) return new Response(JSON.stringify({ token: "inst" }));
    if (url.endsWith("/graphql")) return new Response(JSON.stringify({ data: { repository: { pullRequest: pr } } }));
    if (url.includes("push.apple.com")) { pushes.push({ url, body: JSON.parse(String(init!.body)) }); const s = pushStatus(url); return new Response(s === 200 ? "" : JSON.stringify({ reason: "Unregistered" }), { status: s }); }
    throw new Error("unexpected " + url);
  });
  return { env, pushes };
}
const repository = { name: "r", owner: { login: "o" } };
const suite = { action: "completed", sender: { login: "github" }, installation: { id: 9 }, repository, check_suite: { conclusion: "success", pull_requests: [{ number: 3 }] } };
const kinds = (p: { body: any }[]) => p.map((x) => x.body.mergeable.kind);

describe("handleWebhook", () => {
  it("green check_suite → one push per device, correct hosts (Focus 5)", async () => {
    const { env, pushes } = await setup();
    await handleWebhook(env, "check_suite", suite);
    expect(pushes).toHaveLength(2);
    expect(pushes.map((p) => p.url.split("/")[2]).sort()).toEqual(["api.push.apple.com", "api.sandbox.push.apple.com"]);
    expect(pushes[0]!.body.aps).toMatchObject({ alert: { title: "Ready to merge", subtitle: "o/r #3", body: "T" }, sound: "default", "thread-id": "o/r#3" });
    expect(pushes[0]!.body.mergeable).toMatchObject({ v: 1, kind: "mergeReady", owner: "o", repo: "r", number: 3 });
  });
  it("same delivery twice → one push set", async () => {
    const { env, pushes } = await setup();
    await handleWebhook(env, "check_suite", suite);
    await handleWebhook(env, "check_suite", suite);
    expect(pushes).toHaveLength(2);
  });
  it("self marks ready with green checks → mergeReady only (Focus 1)", async () => {
    const { env, pushes } = await setup();
    await handleWebhook(env, "pull_request", { action: "ready_for_review", sender: { login: "AnthonyPluth" }, installation: { id: 9 }, repository, pull_request: { number: 3, title: "T", html_url: "u" } });
    expect(new Set(kinds(pushes))).toEqual(new Set(["mergeReady"]));
  });
  it("opened PR with no checks → opened + mergeReady (Focus 2)", async () => {
    const { env, pushes } = await setup({ commits: { nodes: [{ commit: { statusCheckRollup: null } }] } });
    await handleWebhook(env, "pull_request", { action: "opened", sender: { login: "bob" }, installation: { id: 9 }, repository, pull_request: { number: 3, title: "T", html_url: "u" } });
    expect(new Set(kinds(pushes))).toEqual(new Set(["opened", "mergeReady"]));
  });
  it("410 removes device", async () => {
    const { env } = await setup({}, (u) => (u.includes("sandbox") ? 410 : 200));
    await handleWebhook(env, "check_suite", suite);
    expect((await listDevices(env.MERGEABLE)).map((d) => d.token)).toEqual(["prod"]);
  });
});

describe("merge-ready retry", () => {
  it("failed delivery releases the claim so a later webhook retries", async () => {
    const { env, pushes } = await setup({}, () => 503);
    await handleWebhook(env, "check_suite", suite);
    expect(pushes).toHaveLength(2);
    await handleWebhook(env, "check_suite", suite);
    expect(pushes).toHaveLength(4);
  });
});
