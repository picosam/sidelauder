#!/bin/sh
# S16: run the Discovery app the way the Dock starts an app (LaunchServices,
# requested from a process holding only the Dock's minimal environment), N times
# on this Mac's own shell setup, then once per fixture shell setup. Prints a
# summary with no paths beyond the Homebrew prefix.
#
# Usage: spikes/s16/discovery.sh <out dir> [runs]
set -eu
out="$1"; runs="${2:-20}"
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../build/Discovery.app/Contents/MacOS/Discovery"
adapter="$here/../../App/Sidelauder/upstream-status.mjs"
mkdir -p "$out"
dock() { env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$app" --via-workspace --adapter "$adapter" "$@"; }
i=1
while [ "$i" -le "$runs" ]; do dock --out "$out/own-$i.json"; i=$((i + 1)); done
for z in empty rc-only noisy slow; do dock --out "$out/fixture-$z.json" --zdotdir "$here/zdotdir/$z"; done
/usr/bin/python3 - "$out" "$runs" <<'PY'
import json, sys, glob, statistics as st
out, runs = sys.argv[1], int(sys.argv[2])
own = [json.load(open(f"{out}/own-{i}.json")) for i in range(1, runs + 1)]
def row(label, rs):
    for v in ("-l", "-l -i"):
        ps = [p for r in rs for p in r["probes"] if p["variant"] == v]
        found = sum(1 for p in ps if p.get("cmp") and p.get("node"))
        ms = sorted(p["milliseconds"] for p in ps)
        print(f"{label:16} {v:6} found both {found}/{len(ps)}  median {st.median(ms):6.0f} ms  max {ms[-1]:6.0f} ms"
              f"  timeouts {sum(p['timedOut'] for p in ps)}  noise bytes {max(p['noiseBytes'] for p in ps)}")
print("app PATH at launch:", sorted({r["launchedPath"] for r in own}))
row("own setup", own)
ad = [r["adapter"] for r in own if r.get("adapter")]
print(f"adapter via found paths: exit 0 in {sum(a['exitCode'] == 0 for a in ad)}/{len(own)}, median {st.median(a['milliseconds'] for a in ad):.0f} ms")
for z in ("empty", "rc-only", "noisy", "slow"):
    row(f"fixture {z}", [json.load(open(f"{out}/fixture-{z}.json"))])
PY
