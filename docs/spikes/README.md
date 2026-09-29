# M0 spike results

The M0 spikes of [spec §16.1](../spec.md), run on the first user's Mac
(macOS 27.0, Apple silicon) from 2026-09-29. Each report gives numbers, a
verdict and the design consequence. Profiles are called A and B; the
recordings, raw logs and anything showing the screen stay off this
repository.

| Spike | Question | Verdict | Report |
|---|---|---|---|
| S16 | Does the interim adapter agree with upstream, what does a call cost, can a Dock-launched app find upstream? | **Pass**: agrees on every state shown; 124 ms per call; found 20/20 | [S16](S16.md) |
| S1 | Can Sidelauder bring a chosen instance forward, after a click and from a hotkey? | **Pass on synthetic input**: 50/50 on every rung, 39 ms click to front; the operator's real-input check is outstanding | [S1](S1.md) |
| S2 | Do hide and unhide work from an app that is not active? | **Pass**: 50/50, under 7 ms | [S2](S2.md) |
| S3 | AX frames on Claude windows: accuracy, minimum size, flicker, ordering | **Accuracy pass** (100/100 within 1 pt); ordering 2 adopted on frame counts; the operator's flicker verdict moves to M1a | [S3](S3.md) |
| S13 | Do the default hotkeys collide? (for D-11) | **Partial**: all register, no system collision; Claude's own shortcuts unchecked | [S1 §Hotkey defaults](S1.md#hotkey-defaults-s13-for-d-11) |
| S11 | Does the Accessibility grant survive rebuilds? | **Observed, not run as a spike**: held across about a dozen rebuilds signed with a development certificate; a grant recorded for an ad-hoc build does not carry over to a certificate-signed one | below |
| S14 | Do hidden or covered instances keep working? | **Pending**: needs the operator | — |
| S15 | Which instance does a notification click activate? | **Pending**: needs the operator | — |

## Operator trials still to run

Each needs the operator's hands; the harness commands are in
[`spikes/Sources/SpikeRunner/main.swift`](../../spikes/Sources/SpikeRunner/main.swift).

1. **S1 real input** (`s1-real`, about 5 minutes): type in profile A, press
   the real hotkey for B, and repeat the other way, 10 times; then 10 real
   clicks on the rail stand-in. This decides R1.
2. **S14** (about 25 minutes): a long chat answer and a Code-tab task in
   profile A, each run visible, hidden and covered, timed with hotkey marks.
3. **S15** (about 15 minutes): prompts in A and in the default instance,
   both hidden, then a click on each notification, 10 clicks in all.
4. **S16, one Dock click** on the Discovery app, to confirm the automated
   Dock-like launches.

Not in this M0 run: S4, S6, S7, S9, S10 and S12. The attached-rail parts of
S4 and S10 were already M1b's; the rest move to the start of M1a.

## S11, observed

The harness was signed with an Apple Development certificate and granted
Accessibility once, then rebuilt about a dozen times; every later run
reported the grant. Before that, one build had run ad hoc, and macOS kept
its entry: the certificate-signed build then failed "to match existing code
requirement", reported not trusted although the switch showed on, and needed
`tccutil reset Accessibility <bundle id>` and a fresh grant. For Phase 0
(§14.2): sign with the stable identity from the first build.
