# M0 spike results

The M0 spikes of [spec §16.1](../spec.md), run on the first user's Mac
(macOS 27.0, Apple silicon) from 2026-09-29. Each report gives numbers, a
verdict and the design consequence. Profiles are called A and B; the
recordings, raw logs and anything showing the screen stay off this
repository.

| Spike | Question | Verdict | Report |
|---|---|---|---|
| S16 | Does the interim adapter agree with upstream, what does a call cost, can a Dock-launched app find upstream? | **Pass**: agrees on every state shown; 124 ms per call; found 20/20 | [S16](S16.md) |
| S1 | Can Sidelauder bring a chosen instance forward, after a click and from a hotkey? | **Pass**: 50/50 on every rung with synthetic input, 39 ms click to front; with the operator's real input, 18/18 hotkeys and 12/12 clicks | [S1](S1.md) |
| S2 | Do hide and unhide work from an app that is not active? | **Pass**: 50/50, under 7 ms | [S2](S2.md) |
| S3 | AX frames on Claude windows: accuracy, minimum size, flicker, ordering | **Accuracy pass** (100/100 within 1 pt); ordering 2 adopted on frame counts; the operator's flicker verdict moves to M1a | [S3](S3.md) |
| S13 | Do the default hotkeys collide? (for D-11) | **Partial**: all register, no system collision; Claude's own shortcuts unchecked | [S1 §Hotkey defaults](S1.md#hotkey-defaults-s13-for-d-11) |
| S11 | Does the Accessibility grant survive rebuilds? | **Observed, not run as a spike**: held across about a dozen rebuilds signed with a development certificate; a grant recorded for an ad-hoc build does not carry over to a certificate-signed one | below |
| S14 | Do hidden or covered instances keep working? | **Pass for chat**: hidden and covered finished no later than visible and were complete at the reveal; hiding cut CPU about sixfold. **Code not measured**: the Code tab asked for approval before every call | [S14](S14.md) |
| S15 | Which instance does a notification click activate? | **Not run**: moved to M1a's daily use by the operator; the harness is ready | [S15](S15.md) |

## Operator trials

Run on 2026-09-29: S1's real-input check ([S1](S1.md#real-input-the-operators-hands))
and S14's chat runs ([S14](S14.md)). Moved to M1a by the operator: S15, and
S16's one Dock click on the Discovery app, which the automated Dock-like
launches already cover. S14's Code-tab part and a hide longer than 5 minutes
are checked in M1a's daily use. The harness commands are in
[`spikes/Sources/SpikeRunner/main.swift`](../../spikes/Sources/SpikeRunner/main.swift).

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
