import type { Env } from "./env";
import { verifySignature } from "./verify";
import { registerDevice, removeDevice, type Device } from "./devices";
import { handleWebhook } from "./handle";

const authed = (req: Request, env: Env) => req.headers.get("authorization") === `Bearer ${env.REGISTRATION_SECRET}`;

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname === "/health") return new Response("ok");
    if (req.method === "POST" && url.pathname === "/webhook") {
      const raw = await req.text();
      if (!(await verifySignature(env.WEBHOOK_SECRET, raw, req.headers.get("x-hub-signature-256")))) return new Response("bad signature", { status: 401 });
      let payload: unknown;
      try { payload = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }
      const event = req.headers.get("x-github-event") ?? "";
      ctx.waitUntil(handleWebhook(env, event, payload).catch((e) => console.error("webhook failed", String(e))));
      return new Response(null, { status: 202 });
    }
    if (url.pathname === "/devices" && req.method === "POST") {
      if (!authed(req, env)) return new Response("unauthorized", { status: 401 });
      let d: Device;
      try { d = (await req.json()) as Device; } catch { return new Response("bad json", { status: 400 }); }
      if (typeof d?.token !== "string" || !d.token || !["ios", "macos"].includes(d.platform) || !["sandbox", "production"].includes(d.environment))
        return new Response("bad device", { status: 400 });
      await registerDevice(env.MERGEABLE, { token: d.token, platform: d.platform, environment: d.environment });
      return new Response(null, { status: 204 });
    }
    if (url.pathname.startsWith("/devices/") && req.method === "DELETE") {
      if (!authed(req, env)) return new Response("unauthorized", { status: 401 });
      await removeDevice(env.MERGEABLE, decodeURIComponent(url.pathname.slice(9)));
      return new Response(null, { status: 204 });
    }
    return new Response("not found", { status: 404 });
  },
};
