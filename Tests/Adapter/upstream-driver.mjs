// Runs the adapter's composition through the REAL installed claude-multiprofile
// against a synthetic process table. Spawned by upstream.test.mjs with HOME and
// XDG_CONFIG_HOME pointing at a fixture, because upstream fixes both paths when
// its modules load.
//
// argv: <adapter module> <claude-multiprofile executable> <ps file> <full: 0|1>

import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [adapterPath, executable, psFile, full] = process.argv.slice(2);
const { packageRootFor, loadUpstream, composeStatus } = await import(pathToFileURL(adapterPath).href);
const up = await loadUpstream(packageRootFor(executable));
const ps = fs.readFileSync(psFile, "utf8");
process.stdout.write(JSON.stringify(composeStatus(up, ps, { full: full === "1" })));
