// Once-per-(PR, head) alerts. KV has no atomic check-and-set, so a short "pending" claim narrows the race window
// between concurrent webhooks; it does not close it. The claim becomes permanent only after a push was delivered,
// and is released on failure so a later webhook can retry.
export async function firstTime(kv: KVNamespace, key: string, ttlSeconds: number): Promise<boolean> {
  if (await kv.get(key)) return false;
  await kv.put(key, "1", { expirationTtl: ttlSeconds });
  return true;
}
export async function claim(kv: KVNamespace, key: string, pendingSeconds = 120): Promise<boolean> {
  if (await kv.get(key)) return false;
  await kv.put(key, "pending", { expirationTtl: pendingSeconds });
  return true;
}
export const confirm = (kv: KVNamespace, key: string, ttlSeconds: number) => kv.put(key, "1", { expirationTtl: ttlSeconds });
export const release = (kv: KVNamespace, key: string) => kv.delete(key);
