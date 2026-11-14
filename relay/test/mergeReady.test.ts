import { describe, it, expect, vi, afterEach } from "vitest";
import { isMergeReady, type PRStatus } from "../src/mergeReady";
import { appJwt, fetchPRStatus, prsForSha } from "../src/githubApp";
import { firstTime } from "../src/dedupe";
import { kv, rsaPem, unb64 } from "./helpers";
afterEach(() => vi.unstubAllGlobals());
const ok: PRStatus = { state: "OPEN", isDraft: false, mergeable: "MERGEABLE", rollup: "SUCCESS", headOid: "h", title: "T", url: "u", author: "a" };

it("isMergeReady table", () => {
  expect(isMergeReady(ok)).toBe(true);
  expect(isMergeReady({ ...ok, isDraft: true })).toBe(false);
  expect(isMergeReady({ ...ok, state: "CLOSED" })).toBe(false);
  expect(isMergeReady({ ...ok, state: "MERGED" })).toBe(false);
  expect(isMergeReady({ ...ok, rollup: "PENDING" })).toBe(false);
  expect(isMergeReady({ ...ok, rollup: "FAILURE" })).toBe(false);
  expect(isMergeReady({ ...ok, mergeable: "CONFLICTING" })).toBe(false);
  expect(isMergeReady({ ...ok, mergeable: "UNKNOWN" })).toBe(true);
  expect(isMergeReady({ ...ok, rollup: null })).toBe(true);
});
it("appJwt verifies", async () => {
  const { pem, pub } = await rsaPem();
  const jwt = await appJwt("42", pem, 1000);
  const [h, c, s] = jwt.split(".");
  expect(JSON.parse(new TextDecoder().decode(unb64(c!)))).toEqual({ iat: 940, exp: 1540, iss: "42" });
  expect(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", pub, unb64(s!), new TextEncoder().encode(`${h}.${c}`))).toBe(true);
});
it("fetchPRStatus maps fixture", async () => {
  const data = { data: { repository: { pullRequest: { title: "T", url: "u", state: "OPEN", isDraft: false, mergeable: "UNKNOWN", headRefOid: "abc", author: { login: "a" }, commits: { nodes: [{ commit: { statusCheckRollup: { state: "SUCCESS" } } }] } } } } };
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify(data)));
  expect(await fetchPRStatus("t", { owner: "o", repo: "r", number: 1 })).toEqual({ state: "OPEN", isDraft: false, mergeable: "UNKNOWN", rollup: "SUCCESS", headOid: "abc", title: "T", url: "u", author: "a" });
  data.data.repository.pullRequest.commits.nodes = [{ commit: { statusCheckRollup: null as any } }];
  expect((await fetchPRStatus("t", { owner: "o", repo: "r", number: 1 })).rollup).toBeNull();
});
it("firstTime true then false", async () => {
  const k = kv();
  expect(await firstTime(k, "x", 10)).toBe(true);
  expect(await firstTime(k, "x", 10)).toBe(false);
});
it("prsForSha drops closed", async () => {
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify([{ number: 1, state: "open" }, { number: 2, state: "closed" }])));
  expect(await prsForSha("t", "o", "r", "s")).toEqual([1]);
});
