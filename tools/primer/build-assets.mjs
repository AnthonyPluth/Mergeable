// Generates the app's Primer colors (dark only; the app is dark-mode only) and Octicons into the asset catalog.
//   node build-assets.mjs [outDir]    default: ../../App/Shared/Assets.xcassets
import { readFileSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] ?? join(here, "../../App/Shared/Assets.xcassets");
const themes = join(here, "node_modules/@primer/primitives/dist/css/functional/themes");
const icons = join(here, "node_modules/@primer/octicons/build/svg");

export const TOKENS = [
  "fgColor-default", "fgColor-muted", "fgColor-accent", "fgColor-open", "fgColor-closed", "fgColor-done",
  "fgColor-success", "fgColor-danger", "fgColor-attention", "bgColor-default", "bgColor-muted", "borderColor-default",
];
export const OCTICONS = [
  "git-pull-request", "git-pull-request-draft", "git-merge", "git-pull-request-closed", "check-circle-fill",
  "x-circle-fill", "dot-fill", "comment", "eye", "check", "file-diff", "bell", "person",
];

export function parseTheme(css) {
  const vars = new Map();
  for (const m of css.matchAll(/--([\w-]+):\s*([^;]+);/g)) vars.set(m[1], m[2].trim());
  const resolve = (name, depth = 0) => {
    const v = vars.get(name);
    if (v === undefined || depth > 8) throw new Error(`token not found: ${name}`);
    const ref = v.match(/^var\(--([\w-]+)\)$/);
    return ref ? resolve(ref[1], depth + 1) : v;
  };
  return resolve;
}

function component(hex) {
  const h = hex.replace("#", "");
  const full = h.length === 3 ? [...h].map((c) => c + c).join("") : h;
  if (!/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(full)) throw new Error(`unsupported color: ${hex}`);
  const n = (i) => (parseInt(full.slice(i, i + 2), 16) / 255).toFixed(3);
  return { red: n(0), green: n(2), blue: n(4), alpha: full.length === 8 ? n(6) : "1.000" };
}

const light = parseTheme(readFileSync(join(themes, "light.css"), "utf8"));
const dark = parseTheme(readFileSync(join(themes, "dark.css"), "utf8"));
const json = (o) => JSON.stringify(o, null, 2) + "\n";
const info = { author: "mergeable", version: 1 };
const colors = {};

rmSync(join(out, "Colors"), { recursive: true, force: true });
rmSync(join(out, "Octicons"), { recursive: true, force: true });
mkdirSync(join(out, "Colors"), { recursive: true });
mkdirSync(join(out, "Octicons"), { recursive: true });
writeFileSync(join(out, "Contents.json"), json({ info }));
for (const sub of ["Colors", "Octicons"]) writeFileSync(join(out, sub, "Contents.json"), json({ info, properties: { "provides-namespace": false } }));

for (const t of TOKENS) {
  const name = t.replace("-", ".");   // fgColor.default
  const l = light(t), d = dark(t);
  colors[name] = { light: l, dark: d };
  const dir = join(out, "Colors", `${name}.colorset`);
  mkdirSync(dir, { recursive: true });
  const entry = (hex) => ({ color: { "color-space": "srgb", components: component(hex) }, idiom: "universal" });
  writeFileSync(join(dir, "Contents.json"), json({ colors: [entry(d)], info }));
}

for (const o of OCTICONS) {
  const dir = join(out, "Octicons", `octicon-${o}.imageset`);
  mkdirSync(dir, { recursive: true });
  copyFileSync(join(icons, `${o}-16.svg`), join(dir, `${o}-16.svg`));
  writeFileSync(join(dir, "Contents.json"), json({
    images: [{ filename: `${o}-16.svg`, idiom: "universal" }],
    info,
    properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
  }));
}

writeFileSync(join(here, "tokens.json"), json(colors));   // consumed by mockups
console.log(`wrote ${TOKENS.length} colorsets and ${OCTICONS.length} octicons to ${out}`);
