import type { PRRef } from "./events";
import type { PRStatus } from "./mergeReady";
import { pemToDer } from "./apns";

const b64url = (b: ArrayBuffer | string): string => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = ""; for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const GH = { accept: "application/vnd.github+json", "user-agent": "mergeable-relay", "x-github-api-version": "2022-11-28" };

export async function appJwt(appId: string, pkcs8Pem: string, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pkcs8Pem), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iat: nowSeconds - 60, exp: nowSeconds + 540, iss: appId }));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(sig)}`;
}

export async function installationToken(jwt: string, installationId: number): Promise<string> {
  const res = await fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
    method: "POST", headers: { ...GH, authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new Error(`installation token: ${res.status}`);
  return ((await res.json()) as { token: string }).token;
}

const QUERY = `query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){title url state isDraft mergeable headRefOid author{login} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}`;

export async function fetchPRStatus(token: string, pr: PRRef): Promise<PRStatus> {
  const res = await fetch("https://api.github.com/graphql", {
    method: "POST", headers: { ...GH, authorization: `bearer ${token}` },
    body: JSON.stringify({ query: QUERY, variables: pr }),
  });
  if (!res.ok) throw new Error(`graphql: ${res.status}`);
  const json = (await res.json()) as any;
  const p = json?.data?.repository?.pullRequest;
  if (!p) throw new Error(`graphql: ${json?.errors?.[0]?.message ?? "no pull request"}`);
  return {
    state: p.state, isDraft: p.isDraft, mergeable: p.mergeable,
    rollup: p.commits?.nodes?.[0]?.commit?.statusCheckRollup?.state ?? null,
    headOid: p.headRefOid, title: p.title, url: p.url, author: p.author?.login ?? null,
  };
}

export async function prsForSha(token: string, owner: string, repo: string, sha: string): Promise<number[]> {
  const res = await fetch(`https://api.github.com/repos/${owner}/${repo}/commits/${sha}/pulls`, { headers: { ...GH, authorization: `bearer ${token}` } });
  if (!res.ok) throw new Error(`commit pulls: ${res.status}`);
  return ((await res.json()) as { number: number; state: string }[]).filter((p) => p.state === "open").map((p) => p.number);
}
