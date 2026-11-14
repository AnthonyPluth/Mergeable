import { describe, it, expect } from "vitest";
import { verifySignature } from "../src/verify";
import { hmacHeader } from "./helpers";
describe("verifySignature", () => {
  it("accepts valid, rejects invalid and missing", async () => {
    const h = await hmacHeader("s", "body");
    expect(await verifySignature("s", "body", h)).toBe(true);
    expect(await verifySignature("s", "body2", h)).toBe(false);
    expect(await verifySignature("s", "body", null)).toBe(false);
    expect(await verifySignature("s", "body", "sha256=zz")).toBe(false);
  });
});
