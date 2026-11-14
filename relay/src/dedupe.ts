export async function firstTime(kv: KVNamespace, key: string, ttlSeconds: number): Promise<boolean> {
  if (await kv.get(key)) return false;
  await kv.put(key, "1", { expirationTtl: ttlSeconds });
  return true;
}
