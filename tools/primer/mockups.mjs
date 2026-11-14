// Renders the sign-off mockups (HTML using the same Primer tokens and Octicons the app uses) to PNGs.
//   node mockups.mjs [outDir]    needs Playwright (preinstalled in the agent container)
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] ?? join(here, "../../docs/mockups");
const tokens = JSON.parse(readFileSync(join(here, "tokens.json"), "utf8"));
const icon = (name, size = 16) =>
  readFileSync(join(here, `node_modules/@primer/octicons/build/svg/${name}-16.svg`), "utf8")
    .replace("<svg", `<svg fill="currentColor" width="${size}" height="${size}" style="flex:none"`);

const cssVars = (mode) => Object.entries(tokens).map(([k, v]) => `--${k.replace(".", "-")}:${v[mode]};`).join("");

const accounts = {
  personal: { label: "Personal", login: "AnthonyPluth", color: "#0969da", bg: "#ddf4ff", dBg: "#388bfd26", dColor: "#58a6ff" },
  work: { label: "Work", login: "apluth-acme", color: "#bc4c00", bg: "#fff1e5", dBg: "#db6d2826", dColor: "#f0883e" },
};
const badge = (a) => `<span class="badge ${a}">${accounts[a].label}</span>`;
const prs = {
  needs: [
    { s: "open", t: "Add retry to webhook delivery", r: "acme/billing #482", by: "dana", age: "2h", ck: "ok", rv: "eye", a: "work" },
    { s: "draft", t: "WIP: migrate sessions to Redis", r: "acme/api #455", by: "marcus", age: "1d", ck: "pend", rv: "", a: "work" },
  ],
  yours: [
    { s: "open", t: "Fix inbox sort when two PRs tie", r: "AnthonyPluth/mergeable #31", by: "you", age: "12m", ck: "ok", rv: "check", a: "personal", ready: true },
    { s: "open", t: "Bump wrangler to 3.91", r: "AnthonyPluth/darkroom #208", by: "dependabot", age: "5h", ck: "fail", rv: "", a: "personal" },
    { s: "open", t: "Cache org membership lookups", r: "acme/api #471", by: "you", age: "1d", ck: "ok", rv: "check", a: "work", ready: true },
  ],
  other: [
    { s: "open", t: "Docs: explain the on-call rotation", r: "acme/handbook #90", by: "priya", age: "3d", ck: "ok", rv: "", a: "work" },
  ],
};
const stateIcon = { open: "git-pull-request", draft: "git-pull-request-draft", merged: "git-merge", closed: "git-pull-request-closed" };
const stateColor = { open: "var(--fgColor-open)", draft: "var(--fgColor-muted)", merged: "var(--fgColor-done)", closed: "var(--fgColor-closed)" };
const ck = { ok: ["check-circle-fill", "var(--fgColor-success)"], fail: ["x-circle-fill", "var(--fgColor-danger)"], pend: ["dot-fill", "var(--fgColor-attention)"] };

const row = (p, selected) => `<div class="row${selected ? " sel" : ""}">
  <span style="color:${stateColor[p.s]};margin-top:2px">${icon(stateIcon[p.s])}</span>
  <div class="main"><div class="title">${p.t}</div>
    <div class="meta">${p.r} · ${p.by} · ${p.age}</div>
    <div class="chips"><span style="color:${ck[p.ck][1]}">${icon(ck[p.ck][0], 14)}</span>${p.rv ? `<span class="muted">${icon(p.rv, 14)}</span>` : ""}${p.ready ? `<span class="ready">Ready to merge</span>` : ""}${badge(p.a)}</div></div></div>`;
const section = (title, list, sel) => `<div class="sec">${title}<span class="count">${list.length}</span></div>${list.map((p) => row(p, sel === p)).join("")}`;
const inbox = (tab, sel) => {
  const f = (l) => (tab === "all" ? l : l.filter((p) => p.a === tab));
  return [["Needs your review", prs.needs], ["Your PRs", prs.yours], ["Assigned or mentioned", prs.other]].map(([t, l]) => f(l).length ? section(t, f(l), sel) : "").join("");
};
const seg = (tab) => `<div class="seg">${["all", "personal", "work"].map((t) => `<span class="${t === tab ? "on" : ""}">${t === "all" ? "All" : accounts[t].label}</span>`).join("")}</div>`;

const detailBody = (acct) => `
  <h1>Cache org membership lookups <span class="num">#471</span></h1>
  <div class="pills"><span class="state">${icon("git-pull-request", 14)} Open</span><span class="muted sm">@apluth-acme wants to merge 2 commits into <code>main</code></span>${badge("work")}</div>
  <div class="card"><div class="ch">Checks <span class="muted">3 of 3 passed</span></div>
    ${[["build", "ok"], ["test (unit)", "ok"], ["lint", "ok"]].map(([n, s]) => `<div class="chk"><span style="color:${ck[s][1]}">${icon(ck[s][0])}</span>${n}</div>`).join("")}</div>
  <div class="card"><div class="ch">Description</div><p>Org membership was fetched on every request. This caches it for 60 seconds per user and clears the cache on the <code>membership</code> webhook.</p></div>
  <div class="card"><div class="ch">Conversation</div>
    <div class="msg"><b>priya</b> <span class="muted">approved · 1h</span><p>Looks good, thanks for the test.</p></div>
    <div class="msg"><b>dana</b> <span class="muted">commented · 40m</span><p>Can we log cache hits?</p></div></div>
  <div class="card files"><span style="color:var(--fgColor-muted)">${icon("file-diff")}</span> Files changed <span class="muted">4 files · +86 −12</span></div>`;
const actions = (compact) => `<div class="actions${compact ? " compact" : ""}">
  <button>${icon("comment")} Comment as @${accounts.work.login}</button>
  <button>${icon("check")} Approve as @${accounts.work.login}</button>
  <button class="primary">${icon("git-merge")} Merge as @${accounts.work.login}</button></div>`;
const sheet = `<div class="scrim"></div><div class="sheet"><div class="grab"></div><h2>Merge pull request</h2>
  <div class="kv"><span>Account</span><b>${badge("work")} @${accounts.work.login}</b></div>
  <div class="kv"><span>Method</span><b>Squash and merge</b></div>
  <div class="kv"><span>Into</span><b><code>main</code></b></div>
  <div class="kv"><span>Head</span><b><code>3f9c1e2</code></b></div>
  <button class="primary wide">${icon("git-merge")} Confirm merge as @${accounts.work.login}</button><button class="wide ghost">Cancel</button></div>`;

const phone = (mode, inner, label) => `<figure><div class="phone ${mode}" style="${cssVars(mode)}"><div class="status"><span>9:41</span><span>●●●</span></div>${inner}</div><figcaption>${label}</figcaption></figure>`;
const phoneInbox = (mode) => `<div class="nav"><h1 class="large">Inbox</h1><span style="color:var(--fgColor-accent)">${icon("bell", 20)}</span></div>${seg("all")}<div class="scroll">${inbox("all")}</div>`;
const phoneDetail = (withSheet) => `<div class="nav back"><span style="color:var(--fgColor-accent)">‹ Inbox</span></div><div class="scroll pad">${detailBody()}</div>${actions(true)}${withSheet ? sheet : ""}`;

const mac = (mode) => `<div class="mac ${mode}" style="${cssVars(mode)}"><div class="titlebar"><i></i><i></i><i></i></div><div class="cols">
  <div class="side"><div class="sh">Accounts</div><div class="si on">${icon("person")} All</div><div class="si">${badge("personal")} ${accounts.personal.login}</div><div class="si">${badge("work")} ${accounts.work.login}</div><div class="sh" style="margin-top:18px">Inbox</div><div class="si sm"><span style="color:var(--fgColor-muted)">${icon("eye")}</span> Needs your review</div><div class="si sm"><span style="color:var(--fgColor-muted)">${icon("git-pull-request")}</span> Your PRs</div><div class="si sm"><span style="color:var(--fgColor-muted)">${icon("comment")}</span> Assigned or mentioned</div></div>
  <div class="list scroll">${inbox("all", prs.yours[2])}</div>
  <div class="det"><div class="scroll pad">${detailBody()}</div>${actions(false)}</div></div></div>`;

const css = readFileSync(join(here, "mockups.css"), "utf8");
const page = (body) => `<!doctype html><meta charset=utf-8><style>${css}</style><body>${body}`;
const sets = {
  "iphone": page(`<div class="phones">${phone("dark", phoneInbox(), "Inbox · All")}${phone("dark", phoneDetail(false), "PR detail")}${phone("dark", phoneDetail(true), "Merge sheet")}</div>`),
  "mac": page(mac("dark")),
};

const { chromium } = createRequire(import.meta.url)("playwright");
mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
for (const [name, html] of Object.entries(sets)) {
  const pg = await browser.newPage({ deviceScaleFactor: 2, viewport: name === "iphone" ? { width: 1300, height: 940 } : { width: 1180, height: 760 } });
  await pg.setContent(html);
  await pg.screenshot({ path: join(out, `${name}.png`), fullPage: true });
  await pg.close();
}
await browser.close();
console.log("wrote", Object.keys(sets).map((n) => `${n}.png`).join(", "), "to", out);
