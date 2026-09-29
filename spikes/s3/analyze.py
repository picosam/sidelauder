#!/usr/bin/env python3
"""S3: find visibly wrong frames in a screen recording of the slot handoff.

Usage:
  analyze.py <recording.mov> <out dir> <anchor video s> <anchor log> <log>...

<anchor video s> is where the anchor log's first click falls in the
recording; every switch of every log is placed on the video by the logs' own
monotonic clock relative to it. The pink flash the runner shows is too short
to find reliably (it lands in one recorded frame, when at all), so the anchor
is found by scanning offsets for the one at which every logged switch shows a
visible change in the slot (spikes/s3/align.py).

For each switch, frames from 150 ms before the click to 300 ms after the last
step are sampled at 60 Hz and two counts are made:
  outside  frames where the screen outside the slot differs from both its
           state before the click and its state after the switch: a window
           shown somewhere other than the slot (variant 1 unhides the target
           where it was, then moves it);
  inside   frames where the slot differs from both before and after: neither
           the source nor the target as it ends up (a blank, a half-drawn
           window, a wrong size).
A clean switch has 0 outside and at most 1 inside (the frame it flips on).

The recording and the extracted frames show the operator's screen: they stay
in <out dir>, outside the repository. Only the counts are published.
Needs ffmpeg and numpy; Pillow for the contact sheets.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

W, H = 512, 288  # analysis frame size; the screen is 16:9
SCREEN_W_PT = 2560.0


def load(logs):
    runs = []
    for p in logs:
        rows = [json.loads(line) for line in open(p) if line.strip()]
        start = next(r for r in rows if r.get("event") == "start")
        switches = [r for r in rows if r.get("spike") == "S3" and "switch" in r and "variant" in r]
        runs.append({"name": Path(p).stem, "start": start, "switches": switches})
    return runs


def frames(video, t0, dur):
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", f"{max(0, t0):.3f}", "-i", video,
           "-t", f"{dur:.3f}", "-vf", f"fps=60,scale={W}:{H},format=gray", "-f", "rawvideo", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    n = len(raw) // (W * H)
    return np.frombuffer(raw[: n * W * H], dtype=np.uint8).reshape(n, H, W)


def differs(a, b, thr=24, frac=0.01):
    return (np.abs(a.astype(np.int16) - b.astype(np.int16)) > thr).mean() > frac


def main():
    video, out, anchor_s, anchor_log, *logs = sys.argv[1:]
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    runs = load([anchor_log] + [l for l in logs if l != anchor_log])
    first_click = runs[0]["switches"][0]["steps"]["click"]
    base_t = runs[0]["start"]["t"] + first_click
    anchor_s = float(anchor_s)
    s = W / SCREEN_W_PT  # analysis pixels per point
    results = []
    for run in runs:
        slot = run["start"]["slot"]
        sx0, sy0 = int(slot["x"] * s), int(slot["y"] * s)
        sx1, sy1 = int((slot["x"] + slot["w"]) * s), min(H, int((slot["y"] + slot["h"]) * s))
        inside = (slice(sy0 + 2, sy1 - 2), slice(sx0 + 2, sx1 - 2))
        mask = np.ones((H, W), bool)
        mask[max(0, sy0 - 2):sy1 + 2, max(0, sx0 - 2):sx1 + 2] = False
        mask[H - 40:, :40] = False  # the rail panel stand-in, bottom left
        origin_s = anchor_s + (run["start"]["t"] - base_t) / 1000.0
        for sw in run["switches"]:
            st = sw["steps"]
            t_click = origin_s + st["click"] / 1000.0
            t_done = origin_s + st["done"] / 1000.0
            f = frames(video, t_click - 0.15, (t_done - t_click) + 0.45)
            if len(f) < 4:
                continue
            before, after = f[0], f[-1]
            n_out = sum(1 for x in f if differs(x[mask], before[mask]) and differs(x[mask], after[mask]))
            n_in = sum(1 for x in f if differs(x[inside], before[inside]) and differs(x[inside], after[inside]))
            # The positive control: the slot must change across the switch (the
            # two profiles' windows look different), or the window missed it.
            changed = differs(after[inside], before[inside], thr=20, frac=0.005)
            results.append({"run": run["name"], "variant": sw["variant"], "switch": sw["switch"],
                            "perturbed": bool(st.get("perturbedTo")), "frames": len(f),
                            "outside": n_out, "inside": n_in, "changed": bool(changed), "videoS": round(t_click, 2)})
    (out / "s3-frames.json").write_text(json.dumps(results, indent=1))
    by = {}
    for r in results:
        by.setdefault((r["variant"], r["perturbed"]), []).append(r)
    print("| Variant | Target moved first | Switches | Slot changed (control) | With any outside frame | Outside frames p50 / max | Inside frames p50 / max | Switches with more than 1 inside frame |")
    print("|---|---|---|---|---|---|---|---|")
    for (v, p), rs in sorted(by.items()):
        o = sorted(r["outside"] for r in rs)
        i = sorted(r["inside"] for r in rs)
        print(f"| {v} | {'yes' if p else 'no'} | {len(rs)} | {sum(1 for r in rs if r['changed'])} | {sum(1 for x in o if x)} | {o[len(o)//2]} / {o[-1]} | "
              f"{i[len(i)//2]} / {i[-1]} | {sum(1 for x in i if x > 1)} |")


if __name__ == "__main__":
    main()
