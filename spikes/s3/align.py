#!/usr/bin/env python3
"""S3: find where the first logged switch falls in the screen recording.

Usage: align.py <recording.mov> <from s> <to s> <log>...

Decodes the span at 60 Hz, 128x72 grey, then scans candidate offsets for the
one at which the slot visibly changes across every logged switch (before the
click vs after the last step). Prints the best offsets; pass the middle of the
plateau to analyze.py.
"""
import json
import subprocess
import sys

import numpy as np

W, H = 128, 72


def main():
    video, t_from, t_to, *logs = sys.argv[1:]
    t_from, t_to = float(t_from), float(t_to)
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(t_from), "-t", str(t_to - t_from),
                          "-i", video, "-vf", f"fps=60,scale={W}:{H},format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    f = np.frombuffer(raw[: len(raw) // (W * H) * W * H], dtype=np.uint8).reshape(-1, H, W).astype(np.int16)
    switches, slot = [], None
    for p in logs:
        rows = [json.loads(line) for line in open(p) if line.strip()]
        start = next(r for r in rows if r.get("event") == "start")
        slot = slot or start["slot"]
        st = start["t"] / 1000
        switches += [(st + r["steps"]["click"] / 1000, st + r["steps"]["done"] / 1000)
                     for r in rows if "switch" in r and "variant" in r]
    s = W / 2560
    x0, y0 = int(slot["x"] * s) + 1, int(slot["y"] * s) + 1
    x1, y1 = int((slot["x"] + slot["w"]) * s) - 1, min(H, int((slot["y"] + slot["h"]) * s)) - 1
    region = f[:, y0:y1, x0:x1]
    base = switches[0][0]
    fi = lambda t: int(round((t - t_from) * 60))
    scores = []
    for o in np.arange(t_from, t_to, 0.02):
        hit = n = 0
        for c, d in switches:
            a, b = fi(c - base + o - 0.15), fi(d - base + o + 0.3)
            if a < 0 or b >= len(region):
                continue
            n += 1
            hit += (np.abs(region[b] - region[a]) > 20).mean() > 0.005
        scores.append((hit / max(n, 1), n, round(float(o), 2)))
    scores.sort(reverse=True)
    print(scores[:8])


if __name__ == "__main__":
    main()
