// Mutation runner for the interim adapter (spec §13.3). Each mutation disables
// one guard in a copy of the adapter; the unit and upstream tests must then
// fail. The unmutated adapter runs first as the control and must pass.
//
// Usage: node Tests/Adapter/mutate.mjs        (exit 0 only if every mutation is red)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const here = path.dirname(new URL(import.meta.url).pathname);
const adapter = path.join(here, "..", "..", "App", "Sidelauder", "upstream-status.mjs");
const tests = ["unit.test.mjs", "upstream.test.mjs", "foundation.test.mjs"].map((t) => path.join(here, t));
const source = fs.readFileSync(adapter, "utf8");

const MUTATIONS = [
  ["own-data-folder check skipped: every copy process is onProfile",
    "if (up.dataDirInUse(p.desktop.dataDir, proc.command)) {", "if (true) {"],
  ["foreign data folder not looked up: it becomes stray",
    "const other = dataDirOwner(proc.command, p.name);", "const other = null;"],
  ["doctor's no-data-folder test dropped (E2): an unregistered folder on the default app becomes the default's",
    "(up.dataDirInUse(desktopDefault.dataDir, proc.command) || !carriesSomeDataDir(proc.command))", "true"],
  ["claim-once dropped (E4): a process can be reported twice",
    "!claimed.has(proc.pid) && claimed.add(proc.pid)", "true"],
  ["account IDs printed instead of names",
    ".map((m) => m.name);", ".map((m) => up.desktopAccountUuid(m.dataDir));"],
  ["--full ignored: launcher bundle IDs always read",
    "bundleId: full && launcherPresent ?", "bundleId: launcherPresent ?"],
  ["--full ignored: copy staleness always read",
    "stale: full && target.dedicatedBundle ?", "stale: target.dedicatedBundle ?"],
  ["version gate skipped",
    "if (!TESTED_VERSIONS.includes(version)) {", "if (false) {"],
  ["argument allowlist dropped",
    "(argv.length === 2 && !full)", "false"],
  ["a process listing of its own imported (GD-10)",
    'import path from "node:path";', 'import path from "node:path";\nimport { execFileSync } from "node:child_process";'],
  ["a file read of its own (GD-10)",
    "return path.dirname(path.dirname(fs.realpathSync(executable)));",
    'fs.readFileSync(path.join(executable, "..", "profiles.json"));\n  return path.dirname(path.dirname(fs.realpathSync(executable)));'],
];

function run(file) {
  const r = spawnSync(process.execPath, ["--test", ...tests], {
    env: { ...process.env, ADAPTER: file },
    encoding: "utf8",
  });
  const fail = /ℹ fail (\d+)/.exec(r.stdout);
  return { status: r.status, failed: fail ? Number(fail[1]) : null };
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sidelauder-mutants-"));
let ok = true;
try {
  const control = path.join(dir, "control.mjs");
  fs.writeFileSync(control, source);
  const c = run(control);
  console.log(`control             ${c.status === 0 ? "green" : "RED"} (${c.failed} failing)`);
  if (c.status !== 0) ok = false;

  MUTATIONS.forEach(([name, from, to], i) => {
    const count = source.split(from).length - 1;
    if (count !== 1) {
      console.log(`mutation ${i + 1}          NOT APPLIED (${count} matches): ${name}`);
      ok = false;
      return;
    }
    const file = path.join(dir, `mutant-${i + 1}.mjs`);
    fs.writeFileSync(file, source.replace(from, to));
    const r = run(file);
    const red = r.status !== 0;
    if (!red) ok = false;
    console.log(`mutation ${String(i + 1).padEnd(2)}         ${red ? "red" : "SURVIVED"} (${r.failed} failing): ${name}`);
  });
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
process.exitCode = ok ? 0 : 1;
