// Integration tests for the interim adapter against the INSTALLED
// claude-multiprofile (spec §13.1: "Adapter tests run against the installed
// upstream on the maintainer's Mac").
//
// Every fixture lives in a throwaway HOME: a registry, launchers compiled with
// osacompile, app copies and data folders with fake account IDs. No real
// profile, data folder or account is read. The process table is synthetic,
// except in the end-to-end run, which reads the live one.
//
// This test FAILS, and does not skip, when claude-multiprofile is not on PATH:
// a gate that passes without its subject would attest nothing.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const here = path.dirname(new URL(import.meta.url).pathname);
const adapter = process.env.ADAPTER ?? path.join(here, "..", "..", "App", "Sidelauder", "upstream-status.mjs");
const driver = path.join(here, "upstream-driver.mjs");

function findExecutable() {
  const r = spawnSync("/bin/sh", ["-c", "command -v claude-multiprofile"], { encoding: "utf8" });
  const exe = r.stdout.trim();
  assert.ok(r.status === 0 && exe, "claude-multiprofile is not on PATH; this gate needs the installed upstream");
  return exe; // the npm link, as onboarding finds it; the adapter resolves it
}
const executable = findExecutable();

// ---- The fixture -------------------------------------------------------------

const home = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "sidelauder-home-")));
const AS = path.join(home, "Library", "Application Support");
const clones = path.join(AS, "claude-multiprofile", "apps");
const plist = (file, dict) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const body = Object.entries(dict).map(([k, v]) => `<key>${k}</key><string>${v}</string>`).join("");
  fs.writeFileSync(file, `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>${body}</dict></plist>`);
};
const app = (p, version, bundleId = "com.anthropic.claudefordesktop") =>
  plist(path.join(p, "Contents", "Info.plist"), { CFBundleIdentifier: bundleId, CFBundleShortVersionString: version });
function launcher(p, name, viaHelper) {
  const line = viaHelper
    ? `do shell script "/usr/bin/osascript -l JavaScript '${home}/Library/Application Support/claude-multiprofile/bin/launch.js' x"`
    : `do shell script "open -n -a /Applications/Claude.app"`;
  fs.mkdirSync(path.dirname(p), { recursive: true });
  execFileSync("/usr/bin/osacompile", ["-o", p, "-e", line], { stdio: "pipe" });
  const info = path.join(p, "Contents", "Info.plist");
  const id = `com.claude-multiprofile.${name}`;
  try {
    execFileSync("/usr/libexec/PlistBuddy", ["-c", `Set :CFBundleIdentifier ${id}`, info], { stdio: "pipe" });
  } catch {
    execFileSync("/usr/libexec/PlistBuddy", ["-c", `Add :CFBundleIdentifier string ${id}`, info], { stdio: "pipe" });
  }
}
const dataDir = (display, account) => {
  const d = path.join(AS, `Claude-${display}`);
  fs.mkdirSync(d, { recursive: true });
  if (account) fs.writeFileSync(path.join(d, "config.json"), JSON.stringify({ lastKnownAccountUuid: account, "oauth:tokenCache": "never-read-by-sidelauder" }));
  return d;
};

const source = path.join(home, "Source", "Claude.app");
app(source, "2.0.0");
const P = {
  work: { display: "Work Space", account: "11111111-fixture", clone: "1.0.0", helper: true },
  cafe: { display: "Café d'été", account: "11111111-fixture", clone: "2.0.0", helper: true },
  solo: { display: "SOLO", account: null, clone: "2.0.0", helper: false },
  legacy: { display: "Legacy", account: "33333333-fixture", clone: null, helper: false },
};
const registry = { version: 1, profiles: [] };
for (const [name, p] of Object.entries(P)) {
  p.dataDir = dataDir(p.display, p.account);
  p.launcher = path.join(home, "Applications", `Claude ${p.display}.app`);
  launcher(p.launcher, name, p.helper);
  p.appPath = p.clone ? path.join(clones, `Claude ${name}.app`) : source;
  if (p.clone) app(p.appPath, p.clone);
  registry.profiles.push({ name, type: "desktop", createdAt: "2026-09-29T00:00:00Z",
    desktop: { dataDir: p.dataDir, appPath: p.launcher, claudeAppPath: source, color: name === "work" ? "teal" : null }, code: null });
}
registry.profiles.push({ name: "cli", type: "code", desktop: null, code: { configDir: path.join(home, ".claude-cli") } });
const config = path.join(home, ".config");
fs.mkdirSync(path.join(config, "claude-multiprofile"), { recursive: true });
fs.writeFileSync(path.join(config, "claude-multiprofile", "profiles.json"), JSON.stringify(registry));
// The default install is /Applications/Claude.app when present (upstream's
// findClaudeApp looks there first) with its data folder under this HOME.
const defaultApp = fs.existsSync("/Applications/Claude.app") ? "/Applications/Claude.app" : null;
const defaultData = path.join(AS, "Claude");
fs.mkdirSync(defaultData, { recursive: true });
fs.writeFileSync(path.join(defaultData, "config.json"), JSON.stringify({ lastKnownAccountUuid: "22222222-fixture" }));

const line = (pid, appPath, args = "") => `${String(pid).padStart(5)} ${appPath}/Contents/MacOS/Claude${args ? " " + args : ""}`;
const env = { PATH: `${path.dirname(process.execPath)}:/usr/bin:/bin`, HOME: home, XDG_CONFIG_HOME: config };

function compose(psLines, full = true) {
  const psFile = path.join(home, `ps-${Math.random().toString(36).slice(2)}.txt`);
  fs.writeFileSync(psFile, psLines.join("\n") + "\n");
  const r = spawnSync(process.execPath, [driver, adapter, executable, psFile, full ? "1" : "0"], { env, encoding: "utf8" });
  fs.rmSync(psFile);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}
const byName = (s, n) => s.profiles.find((p) => p.name === n);

function snapshot(dir) {
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      const st = fs.lstatSync(f);
      out.push(`${f}\t${st.size}\t${st.mtimeMs}`);
      if (e.isDirectory() && !e.isSymbolicLink()) walk(f);
    }
  };
  walk(dir);
  return out.sort().join("\n");
}

// ---- Classification through the real upstream --------------------------------

test("every instance state, through upstream's own runningCopies and dataDirInUse", () => {
  const ps = [
    line(4101, P.work.appPath, `--user-data-dir=${P.work.dataDir}`), // onProfile, space in path
    line(4102, P.cafe.appPath, `--user-data-dir=${P.cafe.dataDir} --enable-x`), // onProfile, unicode and quote
    line(4103, P.solo.appPath), // stray: no data folder
    line(4104, P.solo.appPath, `--user-data-dir=${P.work.dataDir}`), // foreignDataDir, under work
    line(4105, P.solo.appPath, `--user-data-dir=${P.work.dataDir}X`), // stray: a longer, unregistered folder
    line(4106, source, `--user-data-dir=${P.legacy.dataDir}`), // sharedApp: legacy profile on its source app
  ];
  if (defaultApp) {
    ps.push(line(4107, defaultApp)); // the default profile
    ps.push(line(4108, defaultApp, `--user-data-dir=${P.cafe.dataDir}`)); // sharedApp, under cafe
    ps.push(line(4109, defaultApp, `--user-data-dir=${home}/Elsewhere`)); // unregistered: left out
  }
  const s = compose(ps);
  const got = (n) => byName(s, n).instances.map((i) => `${i.pid}:${i.state}`).sort();
  assert.deepEqual(got("work"), ["4101:onProfile", "4104:foreignDataDir"]);
  assert.deepEqual(got("cafe"), defaultApp ? ["4102:onProfile", "4108:sharedApp"] : ["4102:onProfile"]);
  assert.deepEqual(got("solo"), ["4103:stray", "4105:stray"]);
  assert.deepEqual(got("legacy"), ["4106:sharedApp"]);
  if (defaultApp) assert.deepEqual(s.default.instances.map((i) => `${i.pid}:${i.state}`), ["4107:onProfile"]);
  const all = [...s.default.instances, ...s.profiles.flatMap((p) => p.instances)].map((i) => i.pid);
  assert.equal(new Set(all).size, all.length, "a process was reported twice");
});

test("profile facts come from upstream: copies, staleness, launchers, helper use, display names", () => {
  const s = compose([], true);
  assert.deepEqual(s.profiles.map((p) => p.name), ["work", "cafe", "solo", "legacy"], "the Code-only profile is left out");
  assert.equal(s.registry.health, "ok");
  assert.equal(s.registry.path, path.join(config, "claude-multiprofile", "profiles.json"));
  assert.deepEqual(byName(s, "work").app, { path: P.work.appPath, dedicated: true, stale: true });
  assert.deepEqual(byName(s, "cafe").app, { path: P.cafe.appPath, dedicated: true, stale: false });
  assert.deepEqual(byName(s, "legacy").app, { path: source, dedicated: false, stale: null });
  assert.equal(byName(s, "work").launcher.bundleId, "com.claude-multiprofile.work");
  assert.equal(byName(s, "work").launcher.usesHelper, true);
  assert.equal(byName(s, "solo").launcher.usesHelper, false);
  assert.equal(byName(s, "work").displayName, "Work Space");
  assert.equal(byName(s, "cafe").displayName, "Café d'été");
  assert.equal(byName(s, "solo").displayName, "SOLO");
  assert.equal(byName(s, "work").color, "teal");
  assert.equal(s.toolVersion, "0.1.31");
});

test("without --full the spawning facts are null (control for the test above)", () => {
  const s = compose([], false);
  for (const p of s.profiles) {
    assert.equal(p.launcher.bundleId, null);
    assert.equal(p.launcher.usesHelper, null);
    assert.equal(p.app.stale, null);
  }
});

test("shared accounts are named through upstream's desktopAccountUuid; no ID leaves", () => {
  const s = compose([], false);
  assert.deepEqual(byName(s, "work").sharesAccountWith, ["cafe"]);
  assert.deepEqual(byName(s, "cafe").sharesAccountWith, ["work"]);
  assert.deepEqual(byName(s, "solo").sharesAccountWith, []);
  assert.deepEqual(byName(s, "legacy").sharesAccountWith, []);
  const text = JSON.stringify(s);
  for (const id of ["11111111", "22222222", "33333333", "never-read"]) assert.ok(!text.includes(id), `${id} leaked`);
});

test("known limitation: an unregistered Claude.app whose path ends in the default one is reported as the default's", () => {
  // Upstream's runningCopies matches the app path anywhere in the line. The
  // app's liveness check (spec §8.4) compares the process's bundle URL with
  // the reported appPath and discards this PID; this test pins the adapter's
  // side so a change in either is noticed.
  if (!defaultApp) return;
  const s = compose([line(4201, path.join(home, defaultApp))]);
  assert.deepEqual(s.default.instances.map((i) => [i.pid, i.appPath]), [[4201, defaultApp]]);
});

// ---- The real entry point ----------------------------------------------------

test("the adapter as the app runs it: empty environment, live process table, exit 0, nothing written", () => {
  const before = snapshot(home);
  for (const args of [[executable], [executable, "--full"]]) {
    const r = spawnSync(process.execPath, [adapter, ...args], { env: { PATH: env.PATH, HOME: home, XDG_CONFIG_HOME: config }, encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    const s = JSON.parse(r.stdout);
    assert.equal(s.schemaVersion, 1);
    assert.equal(s.profiles.length, 4);
  }
  assert.equal(snapshot(home), before, "the adapter changed something under HOME");
});

test("a corrupt registry is reported, not treated as empty and not rewritten", () => {
  const reg = path.join(config, "claude-multiprofile", "profiles.json");
  const good = fs.readFileSync(reg, "utf8");
  fs.writeFileSync(reg, "{ not json");
  try {
    const s = compose([]);
    assert.equal(s.registry.health, "corrupt");
    assert.deepEqual(s.profiles, []);
    assert.equal(fs.readFileSync(reg, "utf8"), "{ not json");
  } finally {
    fs.writeFileSync(reg, good);
  }
});

test.after(() => fs.rmSync(home, { recursive: true, force: true }));
