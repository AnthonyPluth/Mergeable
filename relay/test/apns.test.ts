import { describe, it, expect, vi, afterEach } from "vitest";
import { providerToken, sendPush, apnsHost } from "../src/apns";
import { p256Pem, unb64 } from "./helpers";

afterEach(() => vi.unstubAllGlobals());

describe("apns", () => {
  it("hosts", () => {
    expect(apnsHost("sandbox")).toBe("api.sandbox.push.apple.com");
    expect(apnsHost("production")).toBe("api.push.apple.com");
  });
  it("providerToken is a verifiable ES256 JWT", async () => {
    const { pem, pub } = await p256Pem();
    const jwt = await providerToken({ keyId: "KID", teamId: "TEAM", p8Pem: pem, topic: "t" }, 1000);
    const [h, c, s] = jwt.split(".");
    expect(JSON.parse(new TextDecoder().decode(unb64(h!)))).toEqual({ alg: "ES256", kid: "KID" });
    expect(JSON.parse(new TextDecoder().decode(unb64(c!)))).toEqual({ iss: "TEAM", iat: 1000 });
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, unb64(s!), new TextEncoder().encode(`${h}.${c}`))).toBe(true);
  });
  it("sendPush uses sandbox url, headers, body, parses reason", async () => {
    const { pem } = await p256Pem();
    const f = vi.fn(async () => new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 }));
    vi.stubGlobal("fetch", f);
    const r = await sendPush({ keyId: "K", teamId: "T", p8Pem: pem, topic: "com.pluth.mergeable" }, "abc", "sandbox", { aps: {} });
    expect(r).toEqual({ status: 400, reason: "BadDeviceToken" });
    const [url, init] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.sandbox.push.apple.com/3/device/abc");
    const h = init.headers as Record<string, string>;
    expect(h["apns-topic"]).toBe("com.pluth.mergeable");
    expect(h["apns-push-type"]).toBe("alert");
    expect(h["apns-priority"]).toBe("10");
    expect(h.authorization).toMatch(/^bearer ey/);
    expect(init.body).toBe('{"aps":{}}');
  });
});
