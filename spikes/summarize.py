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
        s0 = f"{len(step0)}/{len(pre)}" if any(r.get("step0Ok") is not None for r in rs) else "–"
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
    rs = [r for r in rows if r.get("spike") == "S3" and "switch" in r and "variant" in r]
    if not rs:
        return
    by = OrderedDict()
    for r in rs:
        key = f'{r["variant"]}{" perturbed" if r.get("steps", {}).get("perturbedTo") else ""}'
        by.setdefault(key, []).append(r)
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


def quiet_from(samples, pct=5, window=3):
    """The start of the first `window`-second stretch whose median CPU is under
    `pct`: the end of the work. Idle Claude sits at 1-4 %; hidden streaming at
    about 10 %, so a higher threshold ends a hidden run at its start."""
    for r in samples:
        w = [x["cpuPct"] for x in samples if r["sample"] <= x["sample"] < r["sample"] + window]
        if len(w) >= window * 3 and statistics.median(w) < pct:
            return r["sample"]
    return None


def s14(rows):
    runs, cur = [], None
    for r in rows:
        if r.get("spike") != "S14":
            continue
        if r.get("event") == "start":
            cur = {"start": r, "samples": []}
        elif "sample" in r and cur is not None:
            cur["samples"].append(r)
        elif r.get("event") == "revealed" and cur is not None:
            cur["revealed"] = r
        elif r.get("event") == "end" and cur is not None:
            cur["end"] = r
            runs.append(cur)
            cur = None
    print("| Kind | Condition | Applied | Revealed at s | A in front at reveal | Still streaming at reveal | "
          "Finish mark at s | Work ended at s (CPU) | CPU median before the end % |")
    print("|---|---|---|---|---|---|---|---|---|")
    for run in runs:
        e, st, rv = run["end"], run["start"], run.get("revealed", {})
        applied = ", ".join(f"{k}={v}" for k, v in st.get("applied", {}).items() if k != "setFrame") or "–"
        q = quiet_from(run["samples"])
        busy = [x["cpuPct"] for x in run["samples"] if q is None or x["sample"] < q]
        print(f"| {e['kind']} | {e['condition']} | {applied} | {e.get('revealedS') or '–'} | "
              f"{'–' if not rv else ('yes' if rv.get('aFront') else 'no')} | "
              f"{'yes' if e.get('stillStreamingAtReveal') else 'no'} | {e.get('finishedS')}"
              f"{' (stopped)' if e.get('stoppedEarly') else ''} | {fmt1(q)} | "
              f"{fmt1(statistics.median(busy)) if busy else '–'} |")


def fmt1(x):
    return "–" if x is None else f"{x:.1f}"


def s15(rows):
    rs = [r for r in rows if r.get("spike") == "S15" and "click" in r]
    if not rs:
        return
    print("| Click | Declared | Activated | OK | Activations seen |")
    print("|---|---|---|---|---|")
    for r in rs:
        print(f"| {r['click']} | {r['clicked']} | {r['activated']} | {'yes' if r['ok'] else 'no'} | "
              f"{', '.join(r.get('activationsSeen', []))} |")
    print(f"\nPosting instance activated: {sum(1 for r in rs if r['ok'])}/{len(rs)}")


def main():
    rows = []
    for f in sys.argv[1:]:
        with open(f) as fh:
            rows += [json.loads(line) for line in fh if line.strip()]
    for name, fn in (("S1", s1), ("S2", s2), ("S3", s3), ("S14", s14), ("S15", s15)):
        if any(r.get("spike") == name for r in rows):
            print(f"\n### {name}\n")
            fn(rows)


if __name__ == "__main__":
    main()
