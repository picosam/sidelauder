#!/usr/bin/env node
// upstream-status.mjs: Sidelauder's interim adapter (spec §8.1.3).
//
// Prints one JSON document, schema v1, describing the Claude Desktop profiles
// that claude-multiprofile knows about. It exists only until upstream ships a
// read-only `claude-multiprofile status --json` (proposal U1), and is deleted
// the day it does.
//
// Usage: node upstream-status.mjs <claude-multiprofile executable> [--full]
//
// The executable is the absolute path Sidelauder found at onboarding.
// launcher.bundleId, launcher.usesHelper and app.stale each spawn a process
// per profile (PlistBuddy, osadecompile), about 60 ms per profile in all
// (spikes/s16), and change only when a launcher is rebuilt or Claude updates.
// They are read only with --full and are null otherwise. The app asks for
// --full at start and when upstream's config folder changes, and for the
// cheap answer on every Claude launch and exit.
//
// Exit codes:
//   0  the document is on stdout
//   3  upstream is a version this adapter was not tested against; stdout holds
//      {"schemaVersion":1,"error":{"kind":"untestedVersion","toolVersion":...}}
//   1  anything else; the reason is on stderr
//
// The foundation rule (spec §7.0): every fact below comes from a function the
// installed package exports. This file adds no path rule, no process matching
// and no account reading of its own. The exceptions are listed here so a
// reviewer can hold the file to them, and each is proposed upstream in U1:
//
//   E1  displayName is the launcher's file name without "Claude " and ".app".
//       Upstream stores names lowercase and keeps the display casing only in
//       that file name.
//   E2  A process of the default Claude.app whose command line carries a
//       --user-data-dir that is neither a registered profile's nor the default
//       one is left out of the answer (the app treats it as unmanaged). The
//       test is doctor's own, `command.includes("--user-data-dir=")`
//       (commands/doctor.js, checkDesktopLaunchPath), which upstream does not
//       export.
//   E3  The classification into onProfile / stray / foreignDataDir /
//       sharedApp composes upstream's runningCopies and dataDirInUse. Upstream
//       draws the same line inside its launch helper (`onProfile`) and doctor,
//       but exports no function that returns it.
//   E4  runningCopies matches an app path anywhere in a command line, so
//       /Applications/Claude.app also matches ~/Applications/Claude.app. App
//       paths are therefore scanned longest first and a process is reported
//       once, under the first path that claims it. (The launch helper's own
//       `running` matches at the start of the line; upstream exports only the
//       substring form.)
//
// It never writes a file, never runs a command that writes, and makes no
// network call. It never prints an account ID: the account comparison runs in
// upstream's desktopAccountUuid, and only profile names leave this process.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const SCHEMA_VERSION = 1;

// Upstream versions whose internals this adapter was run against. Any other
// version is refused (exit 3) rather than guessed at (spec §8.1.3).
export const TESTED_VERSIONS = ["0.1.31"];

export const EXIT_UNTESTED = 3;

// The launcher file name carries the display casing (E1).
export function displayNameFor(launcherPath) {
  const base = path.basename(launcherPath, ".app");
  return base.startsWith("Claude ") ? base.slice("Claude ".length) : base;
}

// E2, doctor's own test.
function carriesSomeDataDir(command) {
  return command.includes("--user-data-dir=");
}

// Compose the schema v1 document from upstream's functions.
//
// `up` holds the upstream functions (injected, so the composition can be
// tested against fixtures); `ps` is one process-table snapshot, taken by
// upstream's psSnapshot, shared by every classification so they agree.
export function composeStatus(up, ps, { full = false } = {}) {
  const health = up.registryHealth();
  const registry = up.getRegistry();
  const desktopDefault = up.detectDefaults().desktop;
  const profiles = registry.profiles.filter((p) => p && p.desktop);

  const byName = new Map();
  const out = profiles.map((p) => {
    const target = up.launchTargetFor(p.name, p.desktop);
    const launcherPresent = up.fileExists(p.desktop.appPath);
    const entry = {
      name: p.name,
      displayName: displayNameFor(p.desktop.appPath),
      color: p.desktop.color || null,
      launcher: {
        path: p.desktop.appPath,
        present: launcherPresent,
        bundleId: full && launcherPresent ? up.getBundleId(p.desktop.appPath) : null,
        usesHelper: full && launcherPresent ? up.launcherUsesHelper(p.desktop.appPath) ?? null : null,
      },
      app: {
        path: target.claudeAppPath,
        dedicated: target.dedicatedBundle,
        stale: full && target.dedicatedBundle ? up.cloneIsStale(target.claudeAppPath, p.desktop.claudeAppPath) : null,
      },
      dataDir: p.desktop.dataDir,
      instances: [],
      sharesAccountWith: [],
    };
    byName.set(p.name, entry);
    return entry;
  });

  // The registered profile whose data folder this command line runs, if any.
  // dataDirInUse is upstream's matcher (a space or the end must follow the
  // path); handed one command line, it answers for that process alone.
  const dataDirOwner = (command, except) =>
    profiles.find((q) => q.name !== except && up.dataDirInUse(q.desktop.dataDir, command));

  // A process is reported once, under the longest app path that claims it (E4).
  const claimed = new Set();
  const copiesOf = (appPath) =>
    up.runningCopies(appPath, ps).filter((proc) => !claimed.has(proc.pid) && claimed.add(proc.pid));
  const longestFirst = (a, b) => b.length - a.length;

  // Instances of each profile's own app (E3).
  const dedicated = profiles.filter((p) => byName.get(p.name).app.dedicated);
  dedicated.sort((a, b) => longestFirst(byName.get(a.name).app.path, byName.get(b.name).app.path));
  for (const p of dedicated) {
    const appPath = byName.get(p.name).app.path;
    for (const proc of copiesOf(appPath)) {
      const pid = Number(proc.pid);
      if (up.dataDirInUse(p.desktop.dataDir, proc.command)) {
        byName.get(p.name).instances.push({ pid, state: "onProfile", appPath });
        continue;
      }
      const other = dataDirOwner(proc.command, p.name);
      if (other) {
        byName.get(other.name).instances.push({ pid, state: "foreignDataDir", appPath });
      } else {
        byName.get(p.name).instances.push({ pid, state: "stray", appPath });
      }
    }
  }

  // Instances of a shared Claude.app: the default install, and the source app
  // of any profile without its own copy (upstream launches those with
  // `open -n` on the shared app). Such a process belongs to the registered
  // profile whose data folder it runs; on the default app, one with no data
  // folder or the default one is the default profile's (E2, E3).
  const def = desktopDefault
    ? { present: true, appPath: desktopDefault.appPath, dataDir: desktopDefault.dataDir, instances: [], sharesAccountWith: [] }
    : { present: false, appPath: null, dataDir: null, instances: [], sharesAccountWith: [] };
  const sharedApps = new Set();
  if (desktopDefault) sharedApps.add(desktopDefault.appPath);
  for (const e of out) if (!e.app.dedicated) sharedApps.add(e.app.path);
  for (const appPath of [...sharedApps].sort(longestFirst)) {
    for (const proc of copiesOf(appPath)) {
      const pid = Number(proc.pid);
      const owner = dataDirOwner(proc.command, null);
      if (owner) {
        byName.get(owner.name).instances.push({ pid, state: "sharedApp", appPath });
      } else if (
        desktopDefault &&
        appPath === desktopDefault.appPath &&
        (up.dataDirInUse(desktopDefault.dataDir, proc.command) || !carriesSomeDataDir(proc.command))
      ) {
        def.instances.push({ pid, state: "onProfile", appPath });
      }
      // Otherwise: an unregistered data folder on a shared app. Left out;
      // the app treats any Claude process missing from the answer as
      // unmanaged.
    }
  }

  // Which seats share an account, by name only. The IDs stay in this loop.
  const seats = [];
  if (desktopDefault) seats.push({ name: "default", dataDir: desktopDefault.dataDir, sink: def });
  for (const p of profiles) seats.push({ name: p.name, dataDir: p.desktop.dataDir, sink: byName.get(p.name) });
  const groups = new Map();
  for (const s of seats) {
    const id = up.desktopAccountUuid(s.dataDir);
    if (!id) continue;
    if (!groups.has(id)) groups.set(id, []);
    groups.get(id).push(s);
  }
  for (const members of groups.values()) {
    if (members.length < 2) continue;
    for (const s of members) {
      s.sink.sharesAccountWith = members.filter((m) => m !== s).map((m) => m.name);
    }
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    toolVersion: up.toolVersion(),
    helperVersion: up.HELPER_VERSION,
    helperState: up.helperState(),
    registry: { path: up.registryLocation(), health: health.state },
    default: def,
    profiles: out,
  };
}

// The installed package's root, from the executable Sidelauder found at
// onboarding (npm links bin/claude-multiprofile.js into a bin directory).
export function packageRootFor(executable) {
  return path.dirname(path.dirname(fs.realpathSync(executable)));
}

export async function loadUpstream(root) {
  const src = (f) => pathToFileURL(path.join(root, "src", f)).href;
  const [registry, detect, appclone, desktop, helper, state, util] = await Promise.all([
    import(src("registry.js")),
    import(src("detect.js")),
    import(src("appclone.js")),
    import(src("desktop.js")),
    import(src("launchhelper.js")),
    import(src("state.js")),
    import(src("util.js")),
  ]);
  return {
    getRegistry: registry.getRegistry,
    registryHealth: registry.registryHealth,
    registryLocation: registry.registryLocation,
    detectDefaults: detect.detectDefaults,
    clonePathFor: appclone.clonePathFor,
    cloneIsStale: appclone.cloneIsStale,
    runningCopies: appclone.runningCopies,
    psSnapshot: appclone.psSnapshot,
    launchTargetFor: desktop.launchTargetFor,
    dataDirInUse: desktop.dataDirInUse,
    desktopAccountUuid: desktop.desktopAccountUuid,
    getBundleId: desktop.getBundleId,
    launcherUsesHelper: desktop.launcherUsesHelper,
    HELPER_VERSION: helper.HELPER_VERSION,
    helperState: helper.helperState,
    toolVersion: state.toolVersion,
    fileExists: util.fileExists,
  };
}

export async function main(argv, io = { stdout: process.stdout, stderr: process.stderr }) {
  const full = argv[1] === "--full";
  if (argv.length < 1 || argv.length > 2 || (argv.length === 2 && !full) || !path.isAbsolute(argv[0])) {
    io.stderr.write("usage: upstream-status.mjs <absolute path of the claude-multiprofile executable> [--full]\n");
    return 1;
  }
  let root;
  try {
    root = packageRootFor(argv[0]);
  } catch (e) {
    io.stderr.write(`claude-multiprofile not found at ${argv[0]}: ${e.message}\n`);
    return 1;
  }
  // The version gate reads upstream's own version first, through the one
  // module whose shape it needs, before any other internal is imported.
  let version;
  try {
    const state = await import(pathToFileURL(path.join(root, "src", "state.js")).href);
    version = state.toolVersion();
  } catch (e) {
    io.stderr.write(`could not read the claude-multiprofile version: ${e.message}\n`);
    return 1;
  }
  if (!TESTED_VERSIONS.includes(version)) {
    io.stdout.write(JSON.stringify({ schemaVersion: SCHEMA_VERSION, error: { kind: "untestedVersion", toolVersion: version } }) + "\n");
    return EXIT_UNTESTED;
  }
  try {
    const up = await loadUpstream(root);
    io.stdout.write(JSON.stringify(composeStatus(up, up.psSnapshot(), { full })) + "\n");
    return 0;
  } catch (e) {
    io.stderr.write(`claude-multiprofile ${version}: ${e.message}\n`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) {
  process.exitCode = await main(process.argv.slice(2));
}
