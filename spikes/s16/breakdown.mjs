// S16: where the adapter's time goes. Times each upstream call the adapter
// makes, on the live registry, and prints only durations and counts (never
// names or paths), so the output can be pasted into a public report.
//
// Usage: node spikes/s16/breakdown.mjs <claude-multiprofile executable> [runs]
import { performance } from "node:perf_hooks";
import { packageRootFor, loadUpstream, composeStatus } from "../../App/Sidelauder/upstream-status.mjs";

const t0 = performance.now();
const up = await loadUpstream(packageRootFor(process.argv[2]));
const importMs = performance.now() - t0;
const runs = Number(process.argv[3] || 10);

function time(fn) {
  const s = performance.now();
  const r = fn();
  return [performance.now() - s, r];
}
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
const rows = { ps: [], registry: [], defaults: [], bundleId: [], usesHelper: [], stale: [], account: [], compose: [] };
let profiles = 0;
for (let i = 0; i < runs; i++) {
  const [psMs, ps] = time(() => up.psSnapshot());
  rows.ps.push(psMs);
  const [regMs, reg] = time(() => up.getRegistry());
  rows.registry.push(regMs);
  rows.defaults.push(time(() => up.detectDefaults())[0]);
  const ds = reg.profiles.filter((p) => p.desktop);
  profiles = ds.length;
  rows.bundleId.push(ds.reduce((a, p) => a + time(() => up.getBundleId(p.desktop.appPath))[0], 0));
  rows.usesHelper.push(ds.reduce((a, p) => a + time(() => up.launcherUsesHelper(p.desktop.appPath))[0], 0));
  rows.stale.push(ds.reduce((a, p) => a + time(() => up.cloneIsStale(up.clonePathFor(p.name), p.desktop.claudeAppPath))[0], 0));
  rows.account.push(ds.reduce((a, p) => a + time(() => up.desktopAccountUuid(p.desktop.dataDir))[0], 0));
  rows.compose.push(time(() => composeStatus(up, ps))[0]);
}
console.log(JSON.stringify({ profiles, runs, importMs: +importMs.toFixed(1),
  medianMs: Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, +median(v).toFixed(1)])) }, null, 1));
