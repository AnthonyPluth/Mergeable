export async function verifySignature(secret: string, rawBody: string, header: string | null): Promise<boolean> {
  if (!header || !header.startsWith("sha256=")) return false;
  const hex = header.slice(7);
  if (!/^[0-9a-f]{64}$/i.test(hex)) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody)));
  let diff = 0;
  for (let i = 0; i < 32; i++) diff |= mac[i]! ^ parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return diff === 0;
}
