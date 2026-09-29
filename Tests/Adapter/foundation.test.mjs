// Static guard GD-10, the adapter's clause (spec §13.3): the adapter composes
// upstream's exported functions and holds no process listing, file read,
// regular expression or upstream path of its own. A lexical check over code,
// so it catches the ways this file could drift, not every way code can hide
// a read; the unit and upstream tests carry the behaviour.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const adapterPath = process.env.ADAPTER ?? path.join(here, "..", "..", "App", "Sidelauder", "upstream-status.mjs");

// The code without its comments, so the header may name what the code must not do.
function code(text) {
  return text
    .split("\n")
    .map((l) => (l.trimStart().startsWith("//") ? "" : l))
    .join("\n");
}
const src = code(fs.readFileSync(adapterPath, "utf8"));

const FORBIDDEN = [
  ["a child process of its own", /child_process|execFile|spawn\(|exec\(/],
  ["a file read of its own", /readFile|readdir|createReadStream|openSync|statSync|existsSync/],
  ["a file write", /writeFile|appendFile|mkdir|rmSync|renameSync|copyFile|unlink/],
  ["a network module", /node:(http|https|net|dgram|tls|dns)|fetch\(/],
  ["a regular expression", /new RegExp|\.match\(|\.test\(|\/[^/\n*]+\/[gimsuy]*\.(test|exec)|\.(replace|split)\(\s*\//],
  ["upstream's registry or data-folder file names", /profiles\.json|config\.json|lastKnownAccountUuid|state\.json|launch\.log/],
  ["upstream's folder layout", /claude-multiprofile\/apps|Application Support|Contents\/MacOS|\.refreshing/],
  ["the process table", /\bps\b\s*[-"']|psOutput\.split/],
];

for (const [what, re] of FORBIDDEN) {
  test(`the adapter holds no ${what}`, () => {
    const hit = src.split("\n").findIndex((l) => re.test(l));
    assert.equal(hit, -1, `line ${hit + 1}: ${src.split("\n")[hit]}`);
  });
}

test("the adapter imports only node:fs, node:path, node:url and upstream's own modules", () => {
  const imports = [...src.matchAll(/^import .* from "([^"]+)";$/gm)].map((m) => m[1]);
  assert.deepEqual(imports.sort(), ["node:fs", "node:path", "node:url"]);
  const dynamic = [...src.matchAll(/import\(src\("([^"]+)"\)\)/g)].map((m) => m[1]).sort();
  assert.deepEqual(dynamic, ["appclone.js", "desktop.js", "detect.js", "launchhelper.js", "registry.js", "state.js", "util.js"]);
});

test("the only fs call is realpathSync, to find the installed package", () => {
  const calls = [...new Set([...src.matchAll(/\bfs\.(\w+)/g)].map((m) => m[1]))];
  assert.deepEqual(calls, ["realpathSync"]);
});

test("paired control: the guard sees a forbidden line when one is present", () => {
  const planted = code('const x = "profiles.json";\nimport { execFileSync } from "node:child_process";');
  assert.ok(FORBIDDEN.some(([, re]) => planted.split("\n").some((l) => re.test(l))));
});
