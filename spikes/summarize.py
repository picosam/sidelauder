#!/usr/bin/env python3
"""Summarise SpikeRunner result logs (JSON lines) into Markdown tables.

Usage: spikes/summarize.py <results.jsonl>...

The logs name instances A and B only, so the tables can go into the public
spike reports. Latencies are milliseconds from the trigger (the posted
click or hotkey, or the call) to the target's activation notification and to
its window being the front one.
"""
import json
import statistics
import sys
from collections import OrderedDict


def pct(xs, p):
    if not xs:
        return None
    s = sorted(xs)
    return s[min(len(s) - 1, round((len(s) - 1) * p))]


def fmt(x):
    return "–" if x is None else f"{x:.0f}"


def s1(rows):
    by = OrderedDict()
    for r in rows:
        if r.get("spike") == "S1" and "condition" in r and "trial" in r:
            by.setdefault((r["condition"], r.get("actor", "runner")), []).append(r)
    print("| Condition | Actor | Trials | Precondition held | OK (of those) | Allowed | Step 0 OK | Activate p50 / p95 | Front p50 / p95 |")
    print("|---|---|---|---|---|---|---|---|---|")
    for (cond, actor), rs in by.items():
        pre = [r for r in rs if r.get("preconditionOk")]
        ok = [r for r in pre if r.get("ok")]
        allowed = [r for r in pre if r.get("allowed") is True]
        step0 = [r for r in pre if r.get("step0Ok") is True]
        act = [r["activateMs"] for r in ok if isinstance(r.get("activateMs"), (int, float))]
        front = [r["frontMs"] for r in ok if isinstance(r.get("frontMs"), (int, float))]
        s0 = f"{len(step0)}/{len(pre)}" if any("step0Ok" in r for r in rs) else "–"
        al = f"{len(allowed)}/{len(pre)}" if any(r.get("allowed") is not None for r in rs) else "–"
        print(f"| {cond} | {actor} | {len(rs)} | {len(pre)} | {len(ok)}/{len(pre)} | {al} | {s0} | "
              f"{fmt(pct(act, .5))} / {fmt(pct(act, .95))} | {fmt(pct(front, .5))} / {fmt(pct(front, .95))} |")
    errors = [r for r in rows if r.get("spike") == "S1" and r.get("error")]
    if errors:
        print(f"\nErrors: {len(errors)}; first: {errors[0].get('condition')}: {errors[0]['error']}")


def s2(rows):
    rs = [r for r in rows if r.get("spike") == "S2" and "trial" in r]
    if not rs:
        return
    pre = [r for r in rs if r.get("preconditionOk")]
    ok = [r for r in pre if r.get("ok")]
    hide = [r["hideMs"] for r in ok if isinstance(r.get("hideMs"), (int, float))]
    unhide = [r["unhideMs"] for r in ok if isinstance(r.get("unhideMs"), (int, float))]
    moved = sum(1 for r in pre if r.get("frontAfterHide") != "unchanged" or r.get("frontAfterUnhide") != "unchanged")
    print("| Trials | Precondition held | Hide and unhide OK | Hide p50 / p95 | Unhide p50 / p95 | Front app changed |")
    print("|---|---|---|---|---|---|")
    print(f"| {len(rs)} | {len(pre)} | {len(ok)}/{len(pre)} | {fmt(pct(hide, .5))} / {fmt(pct(hide, .95))} | "
          f"{fmt(pct(unhide, .5))} / {fmt(pct(unhide, .95))} | {moved} |")


def s3(rows):
    rs = [r for r in rows if r.get("spike") == "S3" and "switch" in r]
    if not rs:
        return
    by = OrderedDict()
    for r in rs:
        by.setdefault(r["variant"], []).append(r)
    print("| Variant | Switches | Frame within 1 pt | Activated | Source hidden | Window found while hidden | Switch p50 / p95 ms |")
    print("|---|---|---|---|---|---|---|")
    for v, xs in by.items():
        within = sum(1 for r in xs if r.get("within1pt"))
        act = sum(1 for r in xs if r.get("activated"))
        hid = sum(1 for r in xs if r.get("sourceHidden"))
        wh = [r.get("windowFoundWhileHidden") for r in xs if r.get("windowFoundWhileHidden") is not None]
        sw = [r["switchMs"] for r in xs if isinstance(r.get("switchMs"), (int, float))]
        print(f"| {v} | {len(xs)} | {within}/{len(xs)} | {act}/{len(xs)} | {hid}/{len(xs)} | "
              f"{sum(1 for w in wh if w)}/{len(wh) if wh else 0} | {fmt(pct(sw, .5))} / {fmt(pct(sw, .95))} |")
    for r in rows:
        if r.get("event") == "minimumSize":
            print(f"\nMinimum size: asked {r['asked']['w']:.0f}×{r['asked']['h']:.0f}, got "
                  f"{r['actual'].get('w', 0):.0f}×{r['actual'].get('h', 0):.0f}")


def main():
    rows = []
    for f in sys.argv[1:]:
        with open(f) as fh:
            rows += [json.loads(line) for line in fh if line.strip()]
    for name, fn in (("S1", s1), ("S2", s2), ("S3", s3)):
        if any(r.get("spike") == name for r in rows):
            print(f"\n### {name}\n")
            fn(rows)


if __name__ == "__main__":
    main()
