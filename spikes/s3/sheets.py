#!/usr/bin/env python3
"""S3: contact sheets for the operator's flicker review.

Usage: sheets.py <recording.mov> <out dir> <anchor video s> <anchor log> <log>

One row per switch of <log>: every distinct frame from 300 ms before the click
to 150 ms after the last step, at 60 Hz, cropped to the slot and the space to
its right (where a moved window would show). The frames the analyzer flags
are outlined: red for a window outside the slot, orange for a slot frame that
is neither the before nor the after state.

The sheets show the operator's screen and stay in <out dir>.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

TW, TH = 480, 255  # one tile
SCREEN_W_PT, SCREEN_H_PT = 2560.0, 1440.0


def frames_rgb(video, t0, dur, crop_pt, vw, vh):
    x, y, w, h = crop_pt
    k = vw / SCREEN_W_PT
    vf = f"fps=60,crop={int(w*k)}:{int(h*k)}:{int(x*k)}:{int(y*k)},scale={TW}:{TH}"
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", f"{max(0, t0):.3f}", "-i", video,
                          "-t", f"{dur:.3f}", "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    n = len(raw) // (TW * TH * 3)
    return np.frombuffer(raw[: n * TW * TH * 3], dtype=np.uint8).reshape(n, TH, TW, 3)


def main():
    video, out, anchor_s, anchor_log, log = sys.argv[1:]
    out = Path(out)
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                            "-of", "csv=p=0", video], capture_output=True, text=True, check=True).stdout.strip()
    vw, vh = (int(v) for v in probe.split(","))
    load = lambda p: [json.loads(line) for line in open(p) if line.strip()]
    a_rows, rows = load(anchor_log), load(log)
    a_start = next(r for r in a_rows if r.get("event") == "start")
    a_first = next(r for r in a_rows if "switch" in r and "variant" in r)["steps"]["click"]
    start = next(r for r in rows if r.get("event") == "start")
    origin = float(anchor_s) + (start["t"] - a_start["t"] - a_first) / 1000.0
    slot = start["slot"]
    crop = (0, max(0, slot["y"] - 110), min(SCREEN_W_PT, slot["x"] + slot["w"] + 520), 0)
    crop = (crop[0], crop[1], crop[2] - crop[0], SCREEN_H_PT - crop[1])
    sx = lambda v: (v - crop[0]) / crop[2] * TW
    sy = lambda v: (v - crop[1]) / crop[3] * TH
    inside = (int(sy(slot["y"])) + 2, int(sy(slot["y"] + slot["h"])) - 2, int(sx(slot["x"])) + 2, int(sx(slot["x"] + slot["w"])) - 2)
    grid = []
    for sw in (r for r in rows if "switch" in r and "variant" in r):
        st = sw["steps"]
        t_click, t_done = origin + st["click"] / 1000, origin + st["done"] / 1000
        f = frames_rgb(video, t_click - 0.3, (t_done - t_click) + 0.45, crop, vw, vh)
        g = f.mean(axis=3).astype(np.int16)
        keep = [0] + [i for i in range(1, len(f)) if np.abs(g[i] - g[i - 1]).mean() > 0.5]
        before, after = g[0], g[-1]
        mask = np.ones(g[0].shape, bool)
        mask[inside[0] - 3:inside[1] + 3, inside[2] - 3:inside[3] + 3] = False
        def diff(a, b, sel):
            return (np.abs(a[sel] - b[sel]) > 24).mean() > 0.01
        ins = (slice(inside[0], inside[1]), slice(inside[2], inside[3]))
        row = []
        for i in keep[:12]:
            flag = None
            if diff(g[i], before, mask) and diff(g[i], after, mask):
                flag = "red"
            elif diff(g[i], before, ins) and diff(g[i], after, ins):
                flag = "orange"
            row.append((f[i], flag, i))
        if keep[-1] != len(f) - 1:
            row.append((f[-1], None, len(f) - 1))
        grid.append((sw["switch"], row))
    cols = max(len(r) for _, r in grid)
    sheet = Image.new("RGB", (60 + cols * (TW + 4), len(grid) * (TH + 4)), "white")
    d = ImageDraw.Draw(sheet)
    for ri, (k, row) in enumerate(grid):
        y = ri * (TH + 4)
        d.text((6, y + TH // 2), f"#{k}", fill="black")
        for ci, (img, flag, i) in enumerate(row):
            x = 60 + ci * (TW + 4)
            sheet.paste(Image.fromarray(img), (x, y))
            d.text((x + 4, y + 4), f"{i * 1000 // 60 - 300:+d} ms from click", fill="blue")
            if flag:
                d.rectangle([x, y, x + TW - 1, y + TH - 1], outline=flag, width=4)
    name = out / f"sheet-{Path(log).stem}.jpg"
    sheet.save(name, quality=85)
    print(name)


if __name__ == "__main__":
    main()
