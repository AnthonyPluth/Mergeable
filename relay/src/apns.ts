export type ApnsEnvironment = "sandbox" | "production";
export interface ApnsConfig { keyId: string; teamId: string; p8Pem: string; topic: string }

export function apnsHost(env: ApnsEnvironment): string {
  return env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
}

const b64url = (b: ArrayBuffer | Uint8Array | string): string => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

export async function providerToken(cfg: ApnsConfig, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(cfg.p8Pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId }));
  const claims = b64url(JSON.stringify({ iss: cfg.teamId, iat: nowSeconds }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(sig)}`;
}

export async function sendPush(
  cfg: ApnsConfig, deviceToken: string, environment: ApnsEnvironment, body: object,
): Promise<{ status: number; reason?: string }> {
  const jwt = await providerToken(cfg, Math.floor(Date.now() / 1000));
  const res = await fetch(`https://${apnsHost(environment)}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "apns-topic": cfg.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      authorization: `bearer ${jwt}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (res.status === 200) return { status: 200 };
  let reason: string | undefined;
  try { reason = ((await res.json()) as { reason?: string }).reason; } catch { /* no body */ }
  return { status: res.status, reason };
}
