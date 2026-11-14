import type { ApnsEnvironment } from "./apns";
export interface Device { token: string; platform: "ios" | "macos"; environment: ApnsEnvironment }

export const registerDevice = (kv: KVNamespace, d: Device) => kv.put(`device:${d.token}`, JSON.stringify(d));
export const removeDevice = (kv: KVNamespace, token: string) => kv.delete(`device:${token}`);
export async function listDevices(kv: KVNamespace): Promise<Device[]> {
  const out: Device[] = [];
  let cursor: string | undefined;
  do {
    const page = await kv.list({ prefix: "device:", cursor });
    for (const k of page.keys) {
      const v = await kv.get(k.name);
      if (v) out.push(JSON.parse(v) as Device);
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return out;
}
