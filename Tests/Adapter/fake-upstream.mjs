// A stand-in for claude-multiprofile's exported functions, for the adapter's
// unit tests. The matching functions reproduce upstream 0.1.31's semantics
// (appclone.js parseRunningCopies, desktop.js dataDirInUse) so the unit tests
// exercise the adapter's composition; Tests/Adapter/upstream.test.mjs runs the
// same partitions through the real installed functions.

import path from "node:path";

export function runningCopies(copyPath, psOutput) {
  const needle = path.join(copyPath, "Contents", "MacOS") + path.sep;
  const found = [];
  for (const line of psOutput.split("\n")) {
    if (!line.includes(needle)) continue;
    const m = line.trim().match(/^(\d+)\s+(.*)$/);
    if (m) found.push({ pid: m[1], command: m[2] });
  }
  return found;
}

export function dataDirInUse(dataDir, psOutput) {
  const flag = ` --user-data-dir=${dataDir}`;
  return psOutput.split("\n").some((line) => {
    const i = line.indexOf(flag);
    if (i < 0) return false;
    const next = line.charAt(i + flag.length);
    return next === "" || next === " ";
  });
}

export const HOME = "/Users/tester";
export const DEFAULT_APP = "/Applications/Claude.app";
export const DEFAULT_DATA = `${HOME}/Library/Application Support/Claude`;
export const clonePathFor = (name) => `${HOME}/Library/Application Support/claude-multiprofile/apps/Claude ${name}.app`;

export function profile(name, { display = name, color = null, code = false, desktop = true } = {}) {
  return {
    name,
    type: desktop && code ? "both" : desktop ? "desktop" : "code",
    desktop: desktop
      ? {
          dataDir: `${HOME}/Library/Application Support/Claude-${display}`,
          appPath: `${HOME}/Applications/Claude ${display}.app`,
          claudeAppPath: DEFAULT_APP,
          color,
        }
      : null,
    code: code ? { configDir: `${HOME}/.claude-${name}` } : null,
  };
}

// A process line as `ps -axww -o pid=,command=` prints it.
export const proc = (pid, appPath, args = "") =>
  `${String(pid).padStart(5)} ${appPath}/Contents/MacOS/Claude${args ? " " + args : ""}`;

export function fakeUpstream({
  profiles = [],
  health = "ok",
  defaults = { appPath: DEFAULT_APP, dataDir: DEFAULT_DATA },
  clones = null, // names with a dedicated copy; default: every profile
  accounts = {}, // dataDir -> account id
  version = "0.1.31",
  calls = [],
} = {}) {
  const withClone = new Set(clones ?? profiles.map((p) => p.name));
  return {
    registryHealth: () => ({ state: health, path: `${HOME}/.config/claude-multiprofile/profiles.json` }),
    getRegistry: () => ({ version: 1, profiles: health === "ok" ? profiles : [] }),
    registryLocation: () => `${HOME}/.config/claude-multiprofile/profiles.json`,
    detectDefaults: () => ({ desktop: defaults, code: null }),
    clonePathFor,
    launchTargetFor: (name, desktop) =>
      withClone.has(name)
        ? { claudeAppPath: clonePathFor(name), dedicatedBundle: true, sourceAppPath: desktop.claudeAppPath, color: desktop.color || null }
        : { claudeAppPath: desktop.claudeAppPath, dedicatedBundle: false },
    runningCopies,
    dataDirInUse,
    psSnapshot: () => "",
    desktopAccountUuid: (dataDir) => accounts[dataDir] ?? null,
    getBundleId: (p) => (calls.push(["getBundleId", p]), `com.claude-multiprofile.${path.basename(p, ".app").toLowerCase()}`),
    launcherUsesHelper: (p) => (calls.push(["launcherUsesHelper", p]), true),
    cloneIsStale: (c, s) => (calls.push(["cloneIsStale", c, s]), false),
    fileExists: () => true,
    HELPER_VERSION: 1,
    helperState: () => "current",
    toolVersion: () => version,
  };
}
