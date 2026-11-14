export class FakeKV {
  m = new Map<string, string>();
  async get(k: string) { return this.m.get(k) ?? null; }
  async put(k: string, v: string) { this.m.set(k, v); }
  async delete(k: string) { this.m.delete(k); }
  async list(o: { prefix?: string }) {
    const keys = [...this.m.keys()].filter((k) => k.startsWith(o.prefix ?? "")).map((name) => ({ name }));
    return { keys, list_complete: true, cursor: "" };
  }
}
export const kv = () => new FakeKV() as unknown as KVNamespace;
export async function p256Pem(): Promise<{ pem: string; pub: CryptoKey }> {
  const k = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  return { pem: toPem(await crypto.subtle.exportKey("pkcs8", k.privateKey)), pub: k.publicKey };
}
export async function rsaPem(): Promise<{ pem: string; pub: CryptoKey }> {
  const k = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  return { pem: toPem(await crypto.subtle.exportKey("pkcs8", k.privateKey)), pub: k.publicKey };
}
const toPem = (der: ArrayBuffer) => `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;
export const unb64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
export const hmacHeader = async (secret: string, body: string) => {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return "sha256=" + [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
};
