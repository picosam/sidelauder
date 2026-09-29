// Unit tests for the interim adapter's composition (spec §8.1.3), against a
// fake upstream. Every classification the adapter can return, every way a
// process can reach it, and a paired valid control for each refusal.
//
// ADAPTER overrides the module under test (the mutation runner points it at
// a mutated copy).

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { fakeUpstream, profile, proc, clonePathFor, DEFAULT_APP, DEFAULT_DATA } from "./fake-upstream.mjs";

const here = path.dirname(new URL(import.meta.url).pathname);
const adapterPath = process.env.ADAPTER ?? path.join(here, "..", "..", "App", "Sidelauder", "upstream-status.mjs");
const { composeStatus, displayNameFor, main, TESTED_VERSIONS, EXIT_UNTESTED } = await import(pathToFileURL(adapterPath).href);

const work = profile("work", { display: "Work", color: "teal" });
const work2 = profile("work2", { display: "Work2" });
const client = profile("client", { display: "Client" });
const P = (s, name) => s.profiles.find((p) => p.name === name);
const dd = (p) => p.desktop.dataDir;

// ---- Instances on a profile's own copy ------------------------------------

test("own copy with its own data folder is onProfile (control)", () => {
  const ps = proc(501, clonePathFor("work"), `--user-data-dir=${dd(work)}`);
  const s = composeStatus(fakeUpstream({ profiles: [work, client] }), ps);
  assert.deepEqual(P(s, "work").instances, [{ pid: 501, state: "onProfile", appPath: clonePathFor("work") }]);
  assert.deepEqual(P(s, "client").instances, []);
});

test("own copy with no data folder is stray", () => {
  const ps = proc(502, clonePathFor("work"));
  const s = composeStatus(fakeUpstream({ profiles: [work, client] }), ps);
  assert.deepEqual(P(s, "work").instances, [{ pid: 502, state: "stray", appPath: clonePathFor("work") }]);
});

test("own copy with an unregistered data folder is stray", () => {
  const ps = proc(503, clonePathFor("work"), "--user-data-dir=/Users/tester/elsewhere");
  const s = composeStatus(fakeUpstream({ profiles: [work, client] }), ps);
  assert.equal(P(s, "work").instances[0].state, "stray");
});

test("own copy running another profile's data folder is foreignDataDir, listed under that profile", () => {
  const ps = proc(504, clonePathFor("work"), `--user-data-dir=${dd(client)}`);
  const s = composeStatus(fakeUpstream({ profiles: [work, client] }), ps);
  assert.deepEqual(P(s, "work").instances, []);
  assert.deepEqual(P(s, "client").instances, [{ pid: 504, state: "foreignDataDir", appPath: clonePathFor("work") }]);
});

test("a data folder that is a prefix of another does not match it (Work vs Work2)", () => {
  const ps = [
    proc(505, clonePathFor("work"), `--user-data-dir=${dd(work2)}`),
    proc(506, clonePathFor("work2"), `--user-data-dir=${dd(work2)} --flag`),
  ].join("\n");
  const s = composeStatus(fakeUpstream({ profiles: [work, work2] }), ps);
  assert.deepEqual(P(s, "work").instances, []);
  assert.deepEqual(P(s, "work2").instances.map((i) => [i.pid, i.state]).sort(), [[505, "foreignDataDir"], [506, "onProfile"]]);
});

test("helper processes under Contents/Frameworks are not instances", () => {
  const ps = `  507 ${clonePathFor("work")}/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=renderer --user-data-dir=${dd(work)}`;
  const s = composeStatus(fakeUpstream({ profiles: [work] }), ps);
  assert.deepEqual(P(s, "work").instances, []);
});

// ---- Instances on the shared default app ----------------------------------

test("default app with no data folder is the default profile's", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work] }), proc(601, DEFAULT_APP));
  assert.deepEqual(s.default.instances, [{ pid: 601, state: "onProfile", appPath: DEFAULT_APP }]);
});

test("default app with the default data folder named explicitly is the default profile's", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work] }), proc(602, DEFAULT_APP, `--user-data-dir=${DEFAULT_DATA}`));
  assert.equal(s.default.instances[0].state, "onProfile");
});

test("default app with a registered profile's data folder is sharedApp under that profile", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work] }), proc(603, DEFAULT_APP, `--user-data-dir=${dd(work)}`));
  assert.deepEqual(s.default.instances, []);
  assert.deepEqual(P(s, "work").instances, [{ pid: 603, state: "sharedApp", appPath: DEFAULT_APP }]);
});

test("default app with an unregistered data folder is left out of the answer", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work] }), proc(604, DEFAULT_APP, "--user-data-dir=/Users/tester/other-tool/Claude-X"));
  assert.deepEqual(s.default.instances, []);
  assert.deepEqual(P(s, "work").instances, []);
});

test("a profile without its own copy, on its source app, is sharedApp", () => {
  const legacy = { ...client, desktop: { ...client.desktop, claudeAppPath: "/Users/tester/Applications/Claude.app" } };
  const ps = proc(605, "/Users/tester/Applications/Claude.app", `--user-data-dir=${dd(legacy)}`);
  const s = composeStatus(fakeUpstream({ profiles: [work, legacy], clones: ["work"] }), ps);
  const c = P(s, "client");
  assert.equal(c.app.dedicated, false);
  assert.equal(c.app.path, "/Users/tester/Applications/Claude.app");
  assert.deepEqual(c.instances, [{ pid: 605, state: "sharedApp", appPath: "/Users/tester/Applications/Claude.app" }]);
});

test("no default install: no default instances, profiles still classified", () => {
  const ps = [proc(606, DEFAULT_APP), proc(607, clonePathFor("work"), `--user-data-dir=${dd(work)}`)].join("\n");
  const s = composeStatus(fakeUpstream({ profiles: [work], defaults: null }), ps);
  assert.deepEqual(s.default, { present: false, appPath: null, dataDir: null, instances: [], sharesAccountWith: [] });
  assert.equal(P(s, "work").instances[0].state, "onProfile");
});

test("one process is reported once, never under two profiles", () => {
  const ps = [
    proc(701, clonePathFor("work"), `--user-data-dir=${dd(work)}`),
    proc(702, clonePathFor("client")),
    proc(703, DEFAULT_APP),
    proc(704, DEFAULT_APP, `--user-data-dir=${dd(client)}`),
  ].join("\n");
  const s = composeStatus(fakeUpstream({ profiles: [work, client] }), ps);
  const pids = [...s.default.instances, ...s.profiles.flatMap((p) => p.instances)].map((i) => i.pid).sort();
  assert.deepEqual(pids, [701, 702, 703, 704]);
});

// ---- Registry --------------------------------------------------------------

test("a Code-only profile is not listed", () => {
  const codeOnly = profile("cli", { desktop: false, code: true });
  const s = composeStatus(fakeUpstream({ profiles: [work, codeOnly] }), "");
  assert.deepEqual(s.profiles.map((p) => p.name), ["work"]);
});

test("a corrupt registry is reported as such, with no profiles", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work], health: "corrupt" }), "");
  assert.equal(s.registry.health, "corrupt");
  assert.deepEqual(s.profiles, []);
});

test("schema and versions are carried from upstream", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work] }), "");
  assert.equal(s.schemaVersion, 1);
  assert.equal(s.toolVersion, "0.1.31");
  assert.equal(s.helperVersion, 1);
  assert.equal(s.helperState, "current");
  assert.equal(P(s, "work").color, "teal");
  assert.equal(P(s, "work").displayName, "Work");
});

// ---- Accounts: names only --------------------------------------------------

test("two profiles on one account each name the other", () => {
  const accounts = { [dd(work)]: "acct-1111", [dd(client)]: "acct-1111", [DEFAULT_DATA]: "acct-2222" };
  const s = composeStatus(fakeUpstream({ profiles: [work, client, work2], accounts }), "");
  assert.deepEqual(P(s, "work").sharesAccountWith, ["client"]);
  assert.deepEqual(P(s, "client").sharesAccountWith, ["work"]);
  assert.deepEqual(P(s, "work2").sharesAccountWith, []);
  assert.deepEqual(s.default.sharesAccountWith, []);
});

test("the default install sharing an account with a profile is named 'default'", () => {
  const accounts = { [dd(work)]: "acct-3333", [DEFAULT_DATA]: "acct-3333" };
  const s = composeStatus(fakeUpstream({ profiles: [work], accounts }), "");
  assert.deepEqual(s.default.sharesAccountWith, ["work"]);
  assert.deepEqual(P(s, "work").sharesAccountWith, ["default"]);
});

test("three seats on one account each name the other two", () => {
  const accounts = { [dd(work)]: "a", [dd(client)]: "a", [dd(work2)]: "a" };
  const s = composeStatus(fakeUpstream({ profiles: [work, client, work2], accounts, defaults: null }), "");
  assert.deepEqual(P(s, "client").sharesAccountWith, ["work", "work2"]);
});

test("profiles never signed in share nothing (null is not an account)", () => {
  const s = composeStatus(fakeUpstream({ profiles: [work, client], accounts: {} }), "");
  assert.deepEqual(P(s, "work").sharesAccountWith, []);
  assert.deepEqual(P(s, "client").sharesAccountWith, []);
});

test("no account ID appears anywhere in the output", () => {
  const accounts = { [dd(work)]: "8f3e-secret-id", [dd(client)]: "8f3e-secret-id", [DEFAULT_DATA]: "b77a-other-id" };
  const text = JSON.stringify(composeStatus(fakeUpstream({ profiles: [work, client], accounts }), ""));
  assert.ok(!text.includes("8f3e"), "shared account ID leaked");
  assert.ok(!text.includes("b77a"), "unshared account ID leaked");
  assert.ok(text.includes('"sharesAccountWith":["client"]'), "control: the sharing itself is reported");
});

// ---- The spawning facts only with --full -----------------------------------

test("without full, no per-profile process is spawned and those facts are null", () => {
  const calls = [];
  const s = composeStatus(fakeUpstream({ profiles: [work, client], calls }), "");
  assert.deepEqual(calls, []);
  assert.equal(P(s, "work").launcher.bundleId, null);
  assert.equal(P(s, "work").launcher.usesHelper, null);
  assert.equal(P(s, "work").app.stale, null);
});

test("with full, each fact is read once per profile (control)", () => {
  const calls = [];
  const s = composeStatus(fakeUpstream({ profiles: [work, client], calls }), "", { full: true });
  assert.equal(calls.filter((c) => c[0] === "getBundleId").length, 2);
  assert.equal(calls.filter((c) => c[0] === "launcherUsesHelper").length, 2);
  assert.equal(calls.filter((c) => c[0] === "cloneIsStale").length, 2);
  assert.equal(P(s, "work").launcher.bundleId, "com.claude-multiprofile.claude work");
  assert.equal(P(s, "work").launcher.usesHelper, true);
  assert.equal(P(s, "work").app.stale, false);
});

// ---- Display names (E1) ----------------------------------------------------

test("display name is the launcher file name without Claude and .app", () => {
  assert.equal(displayNameFor("/Users/tester/Applications/Claude Work.app"), "Work");
  assert.equal(displayNameFor("/Users/tester/Applications/Claude IPSY.app"), "IPSY");
  assert.equal(displayNameFor("/Users/tester/Applications/Claude Client Acme.app"), "Client Acme");
  assert.equal(displayNameFor("/Users/tester/Applications/Café d'été.app"), "Café d'été");
});

// ---- The command line and the version gate ---------------------------------

function fakePackage(version) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sidelauder-fakepkg-"));
  fs.mkdirSync(path.join(root, "src"));
  fs.mkdirSync(path.join(root, "bin"));
  fs.writeFileSync(path.join(root, "src", "state.js"), `export const toolVersion = () => ${JSON.stringify(version)};\n`);
  fs.writeFileSync(path.join(root, "bin", "claude-multiprofile.js"), "");
  const linkDir = fs.mkdtempSync(path.join(os.tmpdir(), "sidelauder-fakebin-"));
  const link = path.join(linkDir, "claude-multiprofile");
  fs.symlinkSync(path.join(root, "bin", "claude-multiprofile.js"), link);
  return link;
}

function capture() {
  const out = { stdout: "", stderr: "" };
  return { out, io: { stdout: { write: (s) => (out.stdout += s) }, stderr: { write: (s) => (out.stderr += s) } } };
}

test("an untested upstream version is refused with exit 3 and a machine-readable reason", async () => {
  const { out, io } = capture();
  const code = await main([fakePackage("0.1.32")], io);
  assert.equal(code, EXIT_UNTESTED);
  assert.deepEqual(JSON.parse(out.stdout), { schemaVersion: 1, error: { kind: "untestedVersion", toolVersion: "0.1.32" } });
});

test("a tested version passes the gate (control: it fails later, on the missing modules, not at the gate)", async () => {
  const { out, io } = capture();
  const code = await main([fakePackage(TESTED_VERSIONS[0])], io);
  assert.equal(code, 1);
  assert.equal(out.stdout, "");
  assert.match(out.stderr, /^claude-multiprofile 0\.1\.31: /);
});

test("the command line accepts only an absolute executable path and --full", async () => {
  // A real executable, so only the argument shape can cause the refusal.
  const exe = fakePackage("0.1.32");
  for (const argv of [[], ["relative/claude-multiprofile"], [exe, "--fix"], [exe, "doctor"], [exe, "--full", "x"]]) {
    const { out, io } = capture();
    assert.equal(await main(argv, io), 1, JSON.stringify(argv));
    assert.match(out.stderr, /^usage: /, JSON.stringify(argv));
    assert.equal(out.stdout, "");
  }
  // Paired controls: the same executable with an allowed shape reaches the version gate.
  for (const argv of [[exe], [exe, "--full"]]) {
    const { io } = capture();
    assert.equal(await main(argv, io), EXIT_UNTESTED, JSON.stringify(argv));
  }
});

test("a missing executable is a clean failure", async () => {
  const { out, io } = capture();
  assert.equal(await main(["/nonexistent/claude-multiprofile"], io), 1);
  assert.match(out.stderr, /not found/);
});
