# Sidelauder — Specification

**A Slack-style profile rail for Claude Desktop profiles created by `claude-multiprofile`.**

| Field | Value |
|---|---|
| Document | Product and technical specification, v0.3 (after the M0 spikes; what M0 changed is Appendix E, the v0.1 challenge Appendix D) |
| Date | 2026-09-29 |
| Status | **Adopted by the operator 2026-09-29 as the plan for M1a. M0 run: S16, S1 (synthetic and real input), S2, S3 and S14 (chat) have results (`docs/spikes/`); S15 and S14's Code-tab part move to M1a's daily use. D-03, D-11 and the bundling question under D-20 ruled by the operator; D-06 decided on S14 (§18)** |
| Name | **Sidelauder** (D-01, ruled 2026-09-29). It replaced the working name *Switchyard*, which NVIDIA's LLM traffic router holds in the same field (E30). It does not contain "Claude" or "Anthropic"; its resemblance to "Claude" is an accepted, recorded risk (R7) |
| Foundation | **`claude-multiprofile` is the foundation.** Sidelauder re-implements none of its profile knowledge and reads it through one read-only interface (§7.0, §8.1) |
| Scope | macOS companion app. Two modes in the **same first public release**: **Mode A: Floating rail** (no special permission) and **Mode B: Docked rail** (Accessibility permission). Built in stages: M1a delivers the shared core, Mode A and the slot handoff; M1b adds the rail that follows the window (§16.2) |
| Audience | Open source, public **from the first commit** (D-02). First user: the author of this request |
| Platform floor | macOS 26 (D-04) |
| Upstream pinned | `jmdarre-v/claude-multiprofile` v0.1.31 (`a954e81`, 2026-09-27), re-verified against the installed 0.1.31 on 2026-09-29 (E27) |
| Evidence cutoff | 2026-09-29. Every factual claim carries an evidence tag (§0.2); M0 measurements cite their report as E32. |

---

## 0. How to read and challenge this document

### 0.1 Purpose

This spec defines what to build, why each choice was made, and exactly where it could be wrong. The reviewing session should attack the claims tagged `[S]`, `[K]` and `[A]` first. Those are where the design can fail.

### 0.2 Evidence tags

| Tag | Meaning | What a challenger should do |
|---|---|---|
| `[V]` | Verified this session against a primary source: upstream source code read directly, or an official page read in full. The E-id points to §19. | Spot-check if the claim is load-bearing. |
| `[V~]` | Primary source, but read through a summarising fetch tool. The wording may be paraphrased. | Re-read the source before relying on exact wording. |
| `[S]` | Secondary source: forum post, blog, issue thread, third-party code summary. | Look for a primary source, or reproduce it. |
| `[K]` | Platform knowledge that was not re-verified this session. | Verify it, or convert it into a spike (§16.1). |
| `[A]` | Assumption. Each one has an A-id (§19.2) and, where it matters, a spike (S-id). | Treat it as unproven until its spike passes. |
| `[D]` | Design decision or recommendation. Open ones have a D-id (§18). | Challenge the reasoning, not the facts. |

### 0.3 ID conventions

G-goals · NG-non-goals · I-invariants · US-user stories · F-features · GD-guards · S-spikes · R-risks · D-decisions · E-evidence · A-assumptions.

---

## 1. Summary

Sidelauder is a small native macOS app (Swift, AppKit + SwiftUI) that adds a **vertical profile rail**, like Slack's workspace rail, on top of the separate Claude Desktop instances that `claude-multiprofile` creates. Clicking a profile, or pressing a hotkey, brings that profile's Claude window forward and hides the others. The user experiences one Claude with an account switcher; macOS still sees N independent, unmodified Claude apps.

- **Built on `claude-multiprofile`.** Which profiles exist, where their launchers and app copies are, which running process belongs to which profile, which copy is on the wrong account, which profiles share an account: all of it comes from upstream through one read-only interface (§8.1). Sidelauder owns only what upstream does not do: windows, activation, hiding, the rail, hotkeys and its own preferences.
- **Mode A: Floating rail.** The rail sits beside the Claude window on a free screen edge, or collapses to an edge tab when there is no room. Switching launches or focuses the target instance and hides the others. It needs **no special permission** and never moves a window.
- **Mode B: Docked rail.** On a switch, the target window takes the exact size and position of the previous one (the "slot"), so it looks like one window changing accounts; from M1b the rail also attaches to the window's edge. It requires the **Accessibility** permission, the same one window managers such as Rectangle use.

Both modes share one core: the upstream interface, the activation ladder, hotkeys, the rail UI, the sign-in assistant and diagnostics. Mode is a runtime setting (`Auto` / `Floating` / `Docked`). Mode B falls back to Mode A behaviour per switch whenever it cannot act safely (full screen, another Space, permission revoked).

**What it never does:** modify any Claude bundle, data folder, Keychain item, token, update state or upstream file. Open any file inside a Claude data folder. Re-derive what upstream knows. Inject code. Use Electron debugging ports. Intercept sign-in. Send input into Claude. Make network calls. Use private macOS APIs (v1). (§2.3)

**Delivery:** a separate repository (MIT), public from its first commit, plus one upstream proposal: a read-only, machine-readable `status --json` command that becomes Sidelauder's whole read contract (§15). Until upstream ships it, Sidelauder carries a thin adapter that calls upstream's own exported functions (§8.1.3); M0 built it and measured it at 124 ms per call (S16). Phase 0 is a locally built, stably signed app for the first user; Phase 1 is the first signed and notarized release (§14).

---

## 2. Goals, non-goals, invariants

### 2.1 Goals

| ID | Goal | Measure |
|---|---|---|
| G1 | One-click / one-keystroke switching between Claude Desktop profiles | p95 switch latency within §12 targets |
| G2 | Slack-like single-window feel (Mode B) | Target window lands in the slot within ±1 pt of position and size, where the target's minimum size allows |
| G3 | Useful without any special permission (Mode A) | Every Mode A feature works with Accessibility denied |
| G4 | Zero interference with Claude Desktop | Invariants I1–I14 hold; guards GD-1…GD-10 have tests with red mutations |
| G5 | Make the known multi-instance hazards visible and fixable | Stray and duplicate-account states, as upstream reports them, surfaced with one-click remedies that route through upstream's launcher |
| G6 | Public-grade trust | Signed, notarized, no bundled third-party code, SECURITY.md, releases built by CI from tagged source |
| G7 | Build on `claude-multiprofile`, never beside it | Sidelauder's source holds no registry decoder, app-copy path rule, process-to-profile matcher or account reader; each comes from upstream's interface (GD-10) |

### 2.2 Non-goals (v1)

| ID | Non-goal | Why |
|---|---|---|
| NG1 | Embedding Claude windows inside Sidelauder's window | Not possible with public macOS APIs `[K]`. Every workaround breaks G4 (§5.4) |
| NG2 | A web-view shell of claude.ai | Loses the desktop-only features, and Anthropic "does not permit third-party developers to offer Claude.ai login into their own applications" `[V]` E23 |
| NG3 | Creating, renaming or removing profiles | That is upstream's job. Sidelauder points to `claude-multiprofile add` |
| NG4 | Claude Code (terminal) profiles | The terminal surface is out of scope. Rail lists only profiles with a Desktop half |
| NG5 | Reading or aggregating Claude notifications, and Dock badges | No public API `[K]`. Badges would need Accessibility access to the Dock for an unknown payoff; moved to the backlog (§16.4) |
| NG6 | Pooling usage limits across accounts | Policy: limits "assume ordinary, individual usage" `[V]` E23. The README must not market this |
| NG7 | Windows/Linux | Claude Desktop profiles via upstream are macOS-only `[V]` E1 |
| NG8 | Auto-update in v1 | Would break I9 (no network). Revisit via D-10 |
| NG9 | Supporting other profile tools (odahcam, erorplex, manual setups) in v1 | Adapter seam reserved (§7.2); not built |
| NG10 | Re-implementing anything `claude-multiprofile` does: reading its registry, deriving app-copy paths, matching processes to profiles, detecting the default install, comparing accounts, launching profiles | The foundation rule (§7.0). What upstream lacks is proposed upstream first (§15) |

### 2.3 Invariants (hard constraints; each is enforced by a guard in §13.3)

| ID | Invariant | Guard |
|---|---|---|
| I1 | Never write to any Claude bundle (`/Applications/Claude.app`, clones), any Claude data folder, `-3p` policy folder, or upstream-owned file (`profiles.json`, `state.json`, `launch.js`, `launch.log`, launchers) | GD-2 |
| I2 | Never read or write the Keychain | GD-2 (static) |
| I3 | Never open any file inside a Claude data folder. (`config.json` there holds Claude's encrypted sign-in cache next to the account ID, 4.1.25.) Account comparison is upstream's; Sidelauder receives only which profiles share an account | GD-2, GD-10 |
| I4 | Never register for or intercept the `claude://` URL scheme. Sign-in always completes through Anthropic's own flow (E23) | GD-9 (static: Info.plist has no `CFBundleURLTypes` for `claude`) |
| I5 | Never inject code, load Claude's code, or start Claude with debugging or inspection flags | GD-7 |
| I6 | Never synthesize input (keys, clicks) into Claude, and never press AX actions inside Claude's content. Window-level AX only: position, size, minimized, raise, frontmost | GD-4 |
| I7 | Never force-terminate. Quit only via polite `terminate()` after explicit user confirmation | GD-3 |
| I8 | Never set `AXEnhancedUserInterface` or `AXManualAccessibility` to `true` on Claude | GD-5 |
| I9 | No network access of any kind in v1: no telemetry, no update checks. The only upstream command Sidelauder runs is its read-only status output, which makes no network call (4.1.22); never `upgrade` | GD-6 |
| I10 | No private or undocumented macOS APIs (SkyLight/CGS, `dlsym` tricks) in v1 | GD-8 |
| I11 | Act only on a process that upstream classified for the intended profile and that passes the liveness check at the moment of acting: same PID, bundle and start time (§8.4) | GD-1 |
| I12 | Launch registry profiles only through upstream's launcher `.app`; open the Default app only as upstream reports it. Never launch an app copy directly | GD-7 |
| I13 | Sidelauder must never be the reason a Claude window cannot be reached. On quit it unhides the instances it hid (D-15). A crash leaves instances reachable via Dock and Cmd-Tab | Test T-crash |
| I14 | Profile knowledge comes only from upstream's interface (§8.1). Sidelauder parses no upstream file and re-derives no upstream rule | GD-10 (static) |

---

## 3. Users and scenarios

### 3.1 Users

| User | Profile | Implication |
|---|---|---|
| First user (author) | Several Claude accounts (personal, work, clients) via `claude-multiprofile`. macOS 27 on Apple silicon `[V]` E28 | Phase 0 build; the M0 spikes run on macOS 27 |
| Public OSS users | Same pattern; macOS 26–27; some refuse Accessibility | Mode A must stand alone; honest docs |
| Contributors | Swift developers | Small, commented codebase; thin Xcode project |

### 3.2 User stories

| ID | Story | Mode |
|---|---|---|
| US1 | I click the "Work" avatar and my Work Claude comes forward; Personal disappears | A, B |
| US2 | In Docked mode the Work window appears exactly where Personal was, same size | B |
| US3 | I press ⌃⌥2 from anywhere and land in profile 2 | A, B |
| US4 | I press ⌃⌥Tab to flip between my last two profiles | A, B |
| US5 | A profile that isn't running launches through its launcher, then comes forward (and lands in the slot, Mode B) | A, B |
| US6 | I see at a glance which profiles are running, hidden, starting, or on the wrong account | A, B |
| US7 | When two profiles are signed into the same account (as upstream detects it), the rail warns me and walks me through a safe re-sign-in | A, B |
| US8 | I can keep one profile visible, so it stays side by side and is never hidden or moved | A, B |
| US9 | Without granting any permission, I still get the rail, hotkeys and status | A |
| US10 | Quitting Sidelauder leaves my Claude windows as they were, with none left hidden | A, B |
| US11 | I can copy a redacted diagnostics report into a GitHub issue | A, B |

### 3.3 The Slack mental model, mapped

| Slack | Sidelauder |
|---|---|
| Workspace rail | Profile rail (one avatar per Claude Desktop profile, plus "Default") |
| One window, switching workspaces | Mode B: one slot, switching which instance occupies it. Mode A: one visible instance at a time (Solo policy) |
| ⌘1…⌘9 | ⌃⌥1…⌃⌥9 (global; ⌘-digits would collide with other apps — §6.5) |
| Unread badges | Not in v1 (NG5) |
| Other workspaces keep syncing | Hidden instances keep running (long responses, Code tasks continue) `[A]` A18, spike S14 |

---

## 4. Background facts

### 4.1 How `claude-multiprofile` works (upstream @ `a954e81`)

| # | Fact | Tag |
|---|---|---|
| 4.1.1 | Desktop isolation uses Electron's `--user-data-dir`. Launchers are `osacompile`d AppleScript applets in `~/Applications/Claude <NAME>.app` | `[V]` E1, E2 |
| 4.1.2 | Since v0.1.23 every Desktop profile launches its **own APFS clone** of Claude.app at `~/Library/Application Support/claude-multiprofile/apps/Claude <name>.app`. The launcher opens it with `open -a <clone>` (no `-n`), so a second click focuses the existing window | `[V]` E1, E2 (`launchTargetFor`, `desktop.js:470`), E3 (`CLONE_PARENT`, `clonePathFor`) |
| 4.1.3 | Profiles whose clone is missing (older or failed builds) still launch the **shared** `/Applications/Claude.app` with `open -n` | `[V]` E2 (`desktop.js:168,478`) |
| 4.1.4 | Clones keep bundle ID `com.anthropic.claudefordesktop` and Anthropic's Team ID. The colour tint is Finder metadata. Plain signature verification and Gatekeeper pass; `codesign --verify --deep --strict` fails | `[V]` E1, E3 |
| 4.1.5 | Every Claude window is titled "Claude" (`CFBundleName`); upstream cannot change it without breaking signing | `[V]` E1 |
| 4.1.6 | Registry: `~/.config/claude-multiprofile/profiles.json` (or `$XDG_CONFIG_HOME/claude-multiprofile/`), `{"version":1,"profiles":[…]}`. Per profile: `name`, `type`, `desktop: {dataDir, appPath (launcher), claudeAppPath (SOURCE app, not the clone), color}` or `null`, and `code: {configDir, aliasName, shell, rcPath, ghConfigDir}` or `null`. Writes keep a `.bak` | `[V]` E5 |
| 4.1.7 | The clone path is **not** in the registry. Upstream derives it by convention and checks whether it exists | `[V]` E2, E3 |
| 4.1.8 | The launcher runs a JXA launch helper (`~/Library/Application Support/claude-multiprofile/bin/launch.js`, `HELPER_VERSION = 1`). It rebuilds a stale clone (~1 s), re-tints, detects a clone running on the wrong account and **asks** whether to quit and reopen. It never blocks Claude from opening | `[V]` E4 |
| 4.1.9 | Upstream identifies a profile's running process by matching `ps -axww` output: the command path starts with `<clone>/Contents/MacOS/`, and the command contains ` --user-data-dir=<dataDir>` followed by a space or end of line | `[V]` E4 (`running`, `onProfile`) |
| 4.1.10 | Dock-launched processes do not inherit the shell `PATH`, so nothing started from the Dock can rely on Node. An app started with `open` or `NSWorkspace.openApplication` from a shell inherits that shell's environment instead, so a terminal launch is no test of a Dock launch | `[V]` E4 (header comment); E32 (S16) |
| 4.1.11 | Sign-in uses a `claude://` deep link that macOS routes to whichever instance answers. With several running, the token can land in the wrong profile. Upstream's remedy is manual: quit all, open one, sign in | `[V]` E1 |
| 4.1.12 | Account identity is `config.json` → `lastKnownAccountUuid` in each data folder. `doctor` compares it across profiles | `[V]` E2 (`desktopAccountUuid`) |
| 4.1.13 | Clones block their own updater per profile (`disableAutoUpdates` in `Claude-<NAME>-3p/`). The launcher refreshes them from `/Applications/Claude.app`. A profile set to `self-update on` relaunches **without** `--user-data-dir` after an update, landing on the default account | `[V]` E1 |
| 4.1.14 | Launcher bundle IDs are `com.claude-multiprofile.<sanitised-name>` | `[V]` E2 (`uniqueBundleId`) |
| 4.1.15 | The launch log is `~/Library/Application Support/claude-multiprofile/launch.log`, with lines `YYYY-MM-DD HH:MM:SS <label>: <INFO|WARN|ERROR> <message>` | `[V]` E4 |
| 4.1.16 | Upstream has one maintainer. It requires no build tools and uses only tools that ship with macOS plus one npm dependency. SECURITY.md enumerates exactly what it reads and writes | `[V]` E1, E6 |
| 4.1.17 | Upstream CI runs Ubuntu × Node 18/20/22/24, plus a macOS job that fails if any macOS test is skipped | `[V]` E7 |
| 4.1.18 | `abnegate/claude-multiprofile` is a fork stuck at v0.1.24. Its owner's registry opt-out was merged upstream as PR #8. Upstream issues: #1, #2, #4, #9; none asks for a switcher | `[V]` E9 (git log), `[V~]` E8 |
| 4.1.19 | Registry names are stored lowercase (`work`); the display casing exists only in the launcher filename (`Claude Work.app`) and the data-folder name | `[V]` E28 |
| 4.1.20 | Upstream 0.1.31 has no machine-readable output. `list` takes ~90 ms warm and ~1.5 s cold; importing one of its modules from Node takes ~60 ms. The interim adapter's call costs 124 ms median end to end (Node's start ~93 ms, one `ps` ~50 ms); decompiling a launcher's script costs ~50 ms per launcher | `[V]` E27, E28; E32 (S16) |
| 4.1.21 | `rename` moves the data folder and the app copy and changes the launcher's bundle ID, all together | `[V]` E27 (`rename.js`) |
| 4.1.22 | Upstream's read commands make no network call, with one exception: `doctor`, even without `--fix`, asks npm for the latest version (`npm view`). `upgrade` calls npm. (v0.2 said only `upgrade` did; corrected in v0.3.) Sidelauder never runs `doctor` | `[V]` E27, E31 |
| 4.1.23 | Upstream already models the default install (`detectDefaults`, shown by `list` and `status`) | `[V]` E27 |
| 4.1.24 | Upstream exports what a read-only status needs: `getRegistry`, `registryHealth`, `registryLocation`, `detectDefaults`, `clonePathFor`, `launchTargetFor`, `runningCopies`, `psSnapshot`, `dataDirInUse`, `cloneIsStale`, `desktopAccountUuid`, `getBundleId`, `launcherUsesHelper`, `helperState`, `toolVersion`. It exports no function that classifies a process as on-profile or stray (the helper and `doctor` each do it inline) and none that reports a copy being refreshed | `[V]` E27; E32 (S16) |
| 4.1.25 | Each data folder's `config.json` holds `oauth:tokenCache` and `oauth:tokenCacheV2` beside `lastKnownAccountUuid` | `[V]` E28 (key names read, no values) |
| 4.1.26 | `runningCopies` matches an app path anywhere in a process's command line, so `/Applications/Claude.app` also matches `~/Applications/Claude.app`. The helper's own `running` matches at the start of the line | `[V]` E27, E31; E32 (S16) |
| 4.1.27 | Launchers are AppleScript applets. An applet opened while Control is held stops at its startup screen and does not run its script; with Option alone it runs | `[V]` E32 (S1, probe on a throwaway applet) |

### 4.2 macOS platform facts that shape the design

| # | Fact | Tag | Consequence |
|---|---|---|---|
| 4.2.1 | No public API lets one app host another app's window | `[K]` | NG1; orchestrate windows instead |
| 4.2.2 | Since macOS 14, activation is cooperative. Apple's header: `activate` makes the app active "if possible", the framework "does not guarantee that the app will be activated at all", and for cooperative activation "the other application should call `-yieldActivationToApplication:`" first | `[V]` E26 | Switching from a non-active state (hotkeys) is the top technical risk (R1, S1) |
| 4.2.3 | `activate(from:options:)` returns whether "the request has been allowed by the system"; `yieldActivation(to:)` "will not deactivate the current app, nor will it activate the other app". A developer reports yield + activate "silently fails" when the caller isn't frontmost; Apple posted no answer | `[V]` E26; `[S]` E13, E14 | Rail clicks activate Sidelauder first, then yield; hotkeys first bring Sidelauder forward (§9.7 step 0) |
| 4.2.4 | Accessibility can read and set another app's window position and size. Rectangle sets size → position → size because macOS clamps sizes to the current display. On Claude windows it landed within 1 pt in 100 of 100 switches, including on the window of a hidden instance; Claude's minimum window size is 600 × 400 pt | `[V~]` E19; `[V]` E32 (S3) | Mode B frame handoff uses the same sequence; §9.4 sets the frame while the target is hidden |
| 4.2.5 | Rectangle turns off `AXEnhancedUserInterface` before resizing when it finds it on | `[V~]` E19 | D-18 |
| 4.2.6 | Chromium/Electron build their full accessibility tree only when they detect assistive technology (`AXEnhancedUserInterface`, `AXManualAccessibility`). Setting `AXEnhancedUserInterface` makes window positioning sluggish or wrong for window managers | `[S]` E20 | I8; S7 measures our side-effects |
| 4.2.7 | Window bounds and owner PID from `CGWindowListCopyWindowInfo` need no Screen Recording permission. Only `kCGWindowName` is gated | `[S]` E18 | Mode A can find which screen a Claude window is on without any permission |
| 4.2.8 | macOS 15 rejects some global hotkeys (`RegisterEventHotKey`) whose only modifiers are ⌥ or ⌥⇧ (error −9868). Reports disagree on scope (sandboxed apps only, or all apps) and on a 15.2 relaxation. Every report agrees that hotkeys including ⌃ or ⌘ are unaffected | `[S]` E15 | Default hotkeys always include ⌃ |
| 4.2.9 | Precise single-window focusing (AltTab) relies on private SkyLight calls (`_SLPSSetFrontProcessWithOptions`) plus synthetic events | `[S]` E17 | I10 forbids that in v1; the activation ladder is public-API only (D-03) |
| 4.2.10 | Dock badges of other apps can be read through Accessibility on the Dock process: `AXDockItem` → `AXStatusLabel`, with `AXURL` identifying the app | `[S]` E21 | Not used in v1 (NG5) |
| 4.2.11 | Accessibility (TCC) grants key on code identity. Ad-hoc-signed builds are identified by cdhash, so each rebuild loses the grant. A build signed with a development certificate kept its grant across about a dozen rebuilds; an entry recorded for an earlier ad-hoc build of the same bundle ID did not carry over and had to be reset (`tccutil reset`) | `[S]` E22; `[V]` E32 (S11, observed) | Phase 0 signs with the stable identity from the first build (§14.2) |
| 4.2.12 | AX calls are synchronous IPC into the target app; a busy target can stall the caller. `AXUIElementSetMessagingTimeout` bounds this | `[K]` | Dedicated AX thread plus a timeout (§7.4) |
| 4.2.13 | AX and CoreGraphics use top-left-origin global coordinates (y down, origin at the primary display's top-left). AppKit uses bottom-left (y up) | `[K]` | Single conversion function, unit-tested (§9.9) |
| 4.2.14 | A non-sandboxed app can read a same-user process's start time and executable (`sysctl(KERN_PROC_PID)`, `proc_pidpath`) without reading its argv | `[K]` | The liveness check (§8.4). Matching argv to profiles is upstream's |
| 4.2.15 | `NSPanel` can be shown with `orderFrontRegardless()` without activating its app. Clicks on a normal (activating) panel activate the app | `[K]` | Rail = activating panel, shown regardless (§6.1) |
| 4.2.16 | Every app copy keeps bundle ID `com.anthropic.claudefordesktop`, so Notification Center cannot tell profiles apart; which instance a notification click activates is unknown | `[A]` A19 | S15 was not run in M0; M1a's daily use records it. The rail follows whatever gets activated |
| 4.2.17 | Chromium throttles timers and rendering in hidden or fully covered windows, hardest after about 5 minutes hidden; Claude Desktop also runs Code sessions and a VM in separate processes. On macOS 27 a chat answer finished no later hidden or fully covered than in front (12.3 and 13.4 s against 14.1 s), and was complete when brought back. Hidden, the instance used about a sixth of its visible CPU (10 % against 64 %); fully covered it saved nothing (63 %). Hides over 5 minutes and Code sessions are unmeasured | `[K]`; `[V]` E32 (S14) | Solo costs nothing measured and saves energy; Stack does not (D-06). M1a's daily use checks long hides and Code |
| 4.2.18 | The macOS 27 SDK's AppKit headers add no API for hosting or reparenting another app's window (its 27-tagged additions are touch-screen, status-item and presentation options) | `[V]` E26 | NG1 stands |
| 4.2.19 | On macOS 27, an app without Accessibility brought a chosen Claude instance forward in 50 of 50 trials by every public route: after a click on its panel, from a hotkey, and even with a plain `activate` and no input behind it, including right after synthetic typing in the front app. With real input, typing in one profile and then pressing the hotkey or clicking the rail, 18 of 18 hotkeys and 12 of 12 clicks switched, at the same latencies | `[V]` E32 (S1) | The ladder (§9.7) stands; nothing was refused on real input either (R1) |
| 4.2.20 | `NSRunningApplication.hide()` and `unhide()` returned false in 100 of 100 calls that worked | `[V]` E32 (S2) | Confirm by notification and `isHidden` (§9.8) |
| 4.2.21 | Setting `kAXFrontmostAttribute` and raising the main window reports success but brought an instance forward in 1 of 50 cases where another app had just hidden and unhidden it | `[V]` E32 (S1, S2) | Step 3 stays after step 1 (§9.7) |
| 4.2.22 | A synthetic key event's modifier flags stay in the session's modifier state until another event clears them | `[V]` E32 (S1) | Test harnesses clear them; together with 4.1.27 it stalled launchers |
| 4.2.23 | A Code-tab session can ask for approval before every tool call, and kept asking after "Always allow" in S14. A hidden instance waiting for an approval waits until someone shows it | `[V]` E32 (S14) | A documented limit of Solo (§9.10); whether Claude notifies for an approval while hidden is checked at M1a |

### 4.3 Policy facts

| # | Fact | Tag | Consequence |
|---|---|---|---|
| 4.3.1 | "Developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow." | `[V]` E23 | I3, I4; the sign-in assistant only quits and launches |
| 4.3.2 | "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications." | `[V]` E23 | NG2 (web-view shell) |
| 4.3.3 | You "can't use the Claude Code or Anthropic names or logos as part of your own product, feature, or company name … or in a way that suggests Anthropic built, endorses, or is partnered with your product" | `[V]` E23 | D-01 naming; no logos |
| 4.3.4 | Trademark guidelines: "No alterations of our trademarks (changes to color, font, proportion, or otherwise)"; no use implying sponsorship or affiliation | `[V~]` E25 | Default avatars are initials, not tinted Claude icons; marketing screenshots use initials |
| 4.3.5 | Consumer Terms: no sharing of account credentials; no access to the Services "through automated or non-human means"; no reverse engineering; no interference with the Services | `[V~]` E24 | I5, I6: Sidelauder only arranges windows. It never automates Claude or touches its traffic |
| 4.3.6 | "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK." | `[V]` E23 | NG6; README positioning (applied to Desktop by analogy) |

This is not legal advice. The interpretations above are engineering constraints chosen to stay clearly inside the published text. The page quoted as E23 governs Claude Code; Sidelauder applies its credential and naming rules to Claude Desktop by analogy, as the conservative reading. D-01 decides whether to ask Anthropic (`marketing@anthropic.com`) before the public launch.

### 4.4 Prior art

| Tool | What it does | Relevance | Tag |
|---|---|---|---|
| `odahcam/claude-desktop-profiles` | SwiftUI manager: card per profile, running indicators, one-click launch/focus, Spotlight launchers, APFS clones, `--user-data-dir`. No window management | Closest UI; confirms nobody ships a rail or slot | `[V~]` E10 |
| `erorplex/claude-desktop-profiles-macos` | One Claude app; swaps data folders by rename and relaunches; one account at a time | Different model: switching costs a relaunch and interrupts responses | `[V~]` E11 |
| Rectangle | Accessibility window manager | Reference for the AX frame-setting pattern | `[V~]` E19 |
| AltTab | Window switcher using private SkyLight calls | Shows the public-API ceiling for focusing (R1) | `[S]` E17 |

---

## 5. Product definition

### 5.1 Terminology

| Term | Meaning |
|---|---|
| Profile | A Claude Desktop identity: one upstream registry entry with a `desktop` half, or the synthetic **Default** profile (`/Applications/Claude.app` with the default data folder) |
| Instance | A running Claude main process, identified by PID and bundle path; upstream says which profile it belongs to |
| On-profile | An instance upstream classifies as running its profile's app with its profile's data folder |
| Stray | A profile's app copy running **without** its data folder, as upstream classifies it; it shows the default account under the profile's colours (4.1.13) |
| Duplicate account | Two profiles upstream reports as signed into the same account |
| Rail | Sidelauder's vertical panel of profile avatars |
| Slot | Mode B's canonical window frame: where the active profile's window lives (kept-visible profiles excepted) |
| Kept-visible profile | A profile the user excludes from Solo and from the slot, in either mode. It is listed but never hidden or moved |
| Solo / Stack | Switch policy: Solo hides every other visible managed instance, except kept-visible ones, once the target's activation is confirmed; Stack only brings the target forward |
| Upstream interface | `claude-multiprofile`'s read-only status output (§8.1): Sidelauder's only source of profile knowledge |
| Liveness check | The act-time test that a PID upstream reported is still the same process: same PID, bundle and start time (§8.4) |

### 5.2 The two modes

| Aspect | Mode A: Floating rail | Mode B: Docked rail |
|---|---|---|
| Permission | None | Accessibility |
| Rail position | Beside the frontmost Claude window, on the first screen edge with at least the rail's width free (window bounds from CGWindowList, 4.2.7); with no room, an 8 pt edge tab revealed on hover or ⌃⌥0. It never covers a Claude window | M1a: as Mode A. M1b: attached flush to the leading edge of the active window; follows moves and resizes |
| On switch | Launch or activate the target; hide the previous one (Solo) | Plus: move and resize the target window into the slot before it appears |
| Window geometry | Untouched; each instance keeps its own remembered bounds | Slot enforced for profiles not kept visible |
| Make room at screen edge | n/a | Optional: shift or shrink the window so the attached rail fits (F-B4, M1b) |
| External activation (Dock, Cmd-Tab, notification click) | Rail updates its highlight | Rail updates; optionally snaps the window into the slot and applies Solo (D-07) |
| Falls back when | n/a | Accessibility denied or revoked; source or target full screen; target on another Space; target has no standard window. The fallback applies per switch and uses Mode A behaviour |

`Auto` (default, D-05) picks B when Accessibility is trusted, otherwise A. The user can force A even with the permission granted.

### 5.3 Feature list (all in v1 unless marked)

| ID | Feature | A | B | Stage |
|---|---|---|---|---|
| F-C1 | Rail listing Default + upstream's Desktop profiles, user-ordered | ✅ | ✅ | M1a |
| F-C2 | Live state per profile: not running · starting · running (hidden or visible) · active · stray · duplicate account · unavailable; rail-wide: upstream unavailable | ✅ | ✅ | M1a |
| F-C3 | Click to switch; launch through the launcher when not running | ✅ | ✅ | M1a |
| F-C4 | Global hotkeys: 1–9, next/previous, last-two toggle, show rail | ✅ | ✅ | M1a |
| F-C5 | Solo/Stack policy | ✅ | ✅ | M1a |
| F-C6 | Context menu: Switch · Hide · Quit… · Reopen on correct account · Reveal data folder in Finder · Copy terminal command · Keep visible | ✅ | ✅ | M1a |
| F-C7 | Menu bar extra with the same list, a mode switch, settings and diagnostics | ✅ | ✅ | M1a |
| F-C8 | Sign-in assistant (§9.11) | ✅ | ✅ | M1a |
| F-C9 | Live profile changes (upstream re-queried when its registry directory changes) | ✅ | ✅ | M1a |
| F-C10 | Diagnostics report (redacted) | ✅ | ✅ | M1a |
| F-C11 | Unhide-on-quit for instances Sidelauder hid | ✅ | ✅ | M1a |
| F-C12 | Launch at login (off by default) | ✅ | ✅ | M1a |
| F-C13 | Per-profile keep visible (US8) | ✅ | ✅ | M1a |
| F-B1 | Slot frame handoff on switch | — | ✅ | M1a |
| F-B3 | Launch-into-slot | — | ✅ | M1a |
| F-B6 | Slot memory per display configuration | — | ✅ | M1a |
| F-B2 | Rail attached to the active window, following it | — | ✅ | M1b |
| F-B4 | Make room at screen edge | — | ✅ | M1b |

v0.1's F-B5 (per-profile undock, Mode B only) became F-C13, which works in both modes. F-X1 (Dock badges) left v1 (NG5).

### 5.4 Rejected alternatives (so the review doesn't re-open them without new evidence)

| Alternative | Why rejected | Evidence |
|---|---|---|
| Reparent Claude windows into our window | No public API. Private window-server routes need SIP (System Integrity Protection) weakened for some operations | `[K]` |
| Screen-capture mirroring plus input forwarding | Needs Screen Recording and Accessibility. Latency, broken IME, drag-drop and accessibility. Also synthesises input (violates I6) | `[K]` |
| Re-host Claude's `app.asar` in our own Electron | Modifies or rehosts Anthropic's code. Breaks signing, Keychain identity and updates. Likely violates the reverse-engineering and interference terms | `[V~]` E24, `[K]` |
| Drive Claude through `--remote-debugging-port` / CDP | Unauthenticated local port into a signed-in session; automation of the Service | `[V~]` E24, `[K]` |
| Web-view shell of claude.ai with per-account data stores | Loses the desktop features; conflicts with 4.3.2 | `[V]` E23 |
| Intercept `claude://` to fix sign-in routing | Intermediates the sign-in token; conflicts with 4.3.1 | `[V]` E23 |
| Put the app inside upstream's repo | Conflicts with upstream's "no build tools / ships-with-macOS" design and its enumerated trust surface; adds a signing pipeline to a one-maintainer project | `[V]` E1, E6. Decision D-02 |
| Re-derive upstream's profile knowledge in Sidelauder (v0.1's registry decoder, app-copy path rule, process matcher and account reader) | Duplicates upstream and drifts from it; the foundation rule (§7.0) | Ruling, 2026-09-29 |
| Launch an app copy directly when an instance vanishes mid-switch (v0.1's race fallback) | Bypasses the helper's refresh and wrong-account check, and would have to copy the launcher's arguments and environment. The switch re-enters as a launch through the launcher instead | `[V]` E27 (`buildLaunchAppleScript`) |

---

## 6. UX specification

### 6.1 Rail anatomy

```
 Mode A (floating, screen edge)          Mode B (docked to the active Claude window)
 ┌────┐                                   ┌────┬──────────────────────────────────┐
 │ ▌D │  ← Default (active: bar + fill)   │ ▌W │  Claude (Work)                   │
 │  W │  ← Work (running, hidden)         │  D │  ┌──────────┬──────────────────┐ │
 │  C·│  ← Client (starting: spinner)     │  C │  │ chats    │ conversation     │ │
 │  P!│  ← Personal (stray: amber ring)   │  P │  │ sidebar  │                  │ │
 │    │                                   │    │  │ (Claude) │                  │ │
 │ ── │                                   │ ── │  └──────────┴──────────────────┘ │
 │  + │  ← add-profile help               │  + │                                  │
 │  ⚙ │  ← settings                       │  ⚙ │                                  │
 └────┘                                   └────┴──────────────────────────────────┘
                                           rail = separate panel, flush with the window edge
```

| Property | Value `[D]` |
|---|---|
| Width | 64 pt. The rail never covers a Claude window: Mode A picks a free edge or collapses to an edge tab (§6.3); the attached rail (M1b) sits outside the window's frame |
| Item | 40 pt avatar, 8 pt vertical gap, 12 pt top inset |
| Active indicator | 4 pt bar on the outer edge + filled background (Slack pattern) |
| Avatar default | Initials of the display name (upstream's `displayName`, 4.1.19) + profile colour (upstream's colour name mapped to a palette; neutral grey when there is none). Option: the clone's own icon read at runtime (local display only, never shipped) — D-09 |
| Panel | `NSPanel` subclass, activating, `hidesOnDeactivate = false`, level `.floating` **only while** a managed instance or Sidelauder is frontmost; otherwise ordered out (§9.5) |
| Visibility (default) | Shown iff the frontmost app is a managed instance or Sidelauder. Setting: "Always show" (Mode A only) |
| Spaces | `collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenNone]`: follows the active Space, stays out of Mission Control and window cycling; hidden over full-screen windows `[K]`, checked by S10 |
| Tooltip | `<Display name> — <state>` plus the hotkey hint. Never the account UUID |
| Drag to reorder | Yes; order saved in `rail.json` |

### 6.2 Item states

| State | Visual | Click does |
|---|---|---|
| Not running | Desaturated avatar | Launch through the launcher (§9.6) |
| Starting | Avatar + spinner; tooltip "Starting…" (or "Updating Claude copy…" while upstream reports `app.refreshing`, 4.1.8; the interim adapter cannot report it, 4.1.24) | Nothing; the click is coalesced |
| Running, hidden | Normal avatar | Switch |
| Running, visible (not active) | Normal avatar + small dot | Switch |
| Active | Bar + fill | No-op (Mode B: re-snap to the slot) |
| Stray | Amber ring + "!" | Popover: "This copy is open on the default account. Reopen it on <profile>?" → Reopen routes through the launcher, whose helper asks the user (4.1.8) |
| Duplicate account | Red ring | Popover naming the other profile(s) → "Sign-in assistant…" |
| Unavailable | Dashed outline | Popover with upstream's reason (launcher missing or failing the §8.4 check, app copy missing) and `claude-multiprofile doctor` copied to the clipboard; upstream advises reading `doctor` before `doctor --fix` |
| Upstream unavailable (rail-wide) | Rail greyed, with a banner | `claude-multiprofile` not found, failing, timing out or reporting an unsupported schema: the rail keeps the last good state greyed and offers Settings → locate `claude-multiprofile`. No launches or switches until upstream answers |

### 6.3 Mode A behaviour

1. The rail appears beside the frontmost managed window: on the configured side if that screen edge has at least the rail's width free next to the window, otherwise on the other side, otherwise as an 8 pt edge tab that reveals the rail on hover or ⌃⌥0. Window bounds and the owning screen come from a `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` snapshot matched by owner PID; the main screen is the fallback. The rail never covers a Claude window.
2. Switching never moves windows. With Solo, the previously frontmost **managed** instance is hidden once the target is active.
3. With Stack, nothing is hidden.
4. The rail re-evaluates its placement on activation changes and screen-parameter changes. It does not follow drags (no AX); a window moved under the rail is re-checked at the next activation.

### 6.4 Mode B behaviour

Items 1, 3 and 4 arrive in M1b. Until then Mode B places the rail as Mode A does (§6.3) and hands the slot over on every switch.

1. The rail is flush with the leading edge of the active window, the same height, and repositions on AX moved/resized notifications, coalesced to the display refresh (F-B2, S4).
2. Switch = slot handoff (§9.4). The target window takes the slot, comes forward, and the source is hidden (Solo).
3. User moves or resizes the active window → the slot updates → the rail follows.
4. Screen-edge collision: if `window.minX - railWidth < screen.visibleFrame.minX`, then, with Make room on (default), shift the window right by the deficit, shrinking the width if needed to stay inside `visibleFrame`. Otherwise move the rail to the trailing edge.
5. External activation (Dock, Cmd-Tab, notification click): with D-07 on, a target that is not kept visible snaps into the slot and Solo applies. Kept-visible profiles are never touched (US8).
6. Full screen, another Space, no standard window, or Accessibility lost → this switch runs as Mode A. A one-line toast explains why (rate-limited to once per cause per 10 min).

### 6.5 Keyboard

| Action | Default `[D]` D-11 | Notes |
|---|---|---|
| Switch to profile N (rail order) | ⌃⌥1 … ⌃⌥9 | ⌘-digit globals would clobber other apps; ⌥-only is rejected on macOS 15 (4.2.8) |
| Next / previous profile | ⌃⌥] / ⌃⌥[ | Not ⌃⌥↑/↓: those are Rectangle's default half-screen shortcuts `[K]` |
| Toggle last two | ⌃⌥Tab | |
| Show rail (Mode A, when hidden) | ⌃⌥0 | Not ⌃⌥Space: that is macOS's default "select next input source" shortcut `[K]`. Shown with `orderFrontRegardless()`; needs no activation |
| Rail keyboard navigation (rail focused) | ↑/↓, Return, Esc | |

Hotkeys use `RegisterEventHotKey` (no permission `[K]`) and are configurable in Settings. Every default registered on macOS 27 and none collides with an enabled macOS shortcut (S13, partial, E32); Claude Desktop's own menu shortcuts are checked by the operator at M1a's start.

**Launching from a hotkey.** A hotkey for a profile that is not running opens its launcher while the hotkey's Control key is still down, and a launcher opened with Control held stops at its startup screen (4.1.27). Sidelauder therefore never opens a launcher while a modifier key is held: it waits for release, up to 2 s, and otherwise shows "Release the keys to open <profile>" and opens on release (§9.6).

**Known risk:** a hotkey fires while Sidelauder is *not* active, so a plain `activate` of the target may be refused (4.2.3). The ladder first brings Sidelauder itself forward on the strength of the hotkey (§9.7 step 0), then hands activation over as a rail click does. S1 measured it: step 0 then step 1 brought the target forward 100/100 on synthetic input, 38 ms median to its window, and 18/18 when the operator typed in one profile and pressed the real hotkey, 42 ms median (4.2.19, R1).

### 6.6 Menu bar extra

A neutral glyph (not a Claude logo). The menu contains:
- the profile list with state and shortcut;
- the mode (Auto / Floating / Docked) and policy (Solo / Stack) selectors;
- Show rail · Sign-in assistant… · Copy diagnostics · Settings… · Quit Sidelauder.

Sidelauder is an agent app (`LSUIElement = YES`): no Dock tile, no Cmd-Tab entry `[D]`.

### 6.7 Onboarding (first run)

1. **Welcome:** what it does and what it never does (the §2.3 invariants in plain language), plus the "unofficial, not affiliated with Anthropic" line.
2. **Discovery:** locate `claude-multiprofile`. A Dock-launched app has no shell `PATH` (4.1.10), so Sidelauder asks the user's login shell once: the shell from the user record (`getpwuid`), first with `-l -c`, then, if either path is missing, with `-l -i -c` (setups that live only in `.zshrc`), each running `command -v claude-multiprofile`, `command -v node` and `printenv XDG_CONFIG_HOME` between marker lines, so rc-file output is ignored. Each probe is its own process group, killed at 5 s (an interactive zsh ignores SIGTERM), and a timed-out probe's answer is dropped. Sidelauder shows what it found and stores the absolute paths once the user confirms; the probe does not run again unless the user asks. Missing → copy `npm install -g claude-multiprofile && claude-multiprofile add`; the rail stays disabled until upstream answers. "Choose location…" covers unusual installs. S16 found both paths in 20 of 20 Dock-style launches, `-l` in 95 ms median (E32).
3. **Mode choice:** Floating (no permission) or Docked. Docked calls `AXIsProcessTrustedWithOptions(prompt: true)` and opens System Settings → Privacy & Security → Accessibility `[K]`. It shows live trust status, polled at 1 Hz only while this screen is open.
4. **Hotkeys:** shows the defaults, with a link to Settings.
5. **Done:** the rail appears the next time a Claude profile is frontmost.

If the permission is revoked at runtime (AX calls return `kAXErrorAPIDisabled`, or `AXIsProcessTrusted()` flips to false), switch to A, show a banner, and keep the chosen mode as the preference.

### 6.8 Settings

| Group | Setting | Default |
|---|---|---|
| General | Mode: Auto / Floating / Docked | Auto |
| | Policy: Solo / Stack | Solo |
| | Show Default profile | On (D-14) |
| | Rail side: Leading / Trailing | Leading |
| | Show rail: When a profile is frontmost / Always (A) | When frontmost |
| | Launch at login (`SMAppService.mainApp`) | Off (D-13) |
| | Unhide hidden profiles when quitting | On (D-15) |
| | Per-profile Keep visible | Off |
| Docked | Match slot on switch | On |
| | Make room at screen edge | On |
| | Snap external activations into slot | On (D-07) |
| Appearance | Avatar: Initials / App icon | Initials (D-09) |
| | Nickname and colour override per profile | — |
| Accounts | Show upstream's duplicate-account warning (Sidelauder reads no account data) | On |
| Keyboard | Hotkey recorder per action | §6.5 |
| Advanced | `claude-multiprofile` and `node` locations | Found at onboarding |
| | Log level | Default |

### 6.9 Copy and tone

- Terminology matches upstream: "profile", "launcher", "Default".
- Never say "Claude's account switcher", and never use Anthropic logos. Referential plain-text only: "works with Claude Desktop profiles created by claude-multiprofile" (§4.3).
- About panel: "Unofficial. Not affiliated with or endorsed by Anthropic."

### 6.10 Accessibility of Sidelauder's own UI

- Each rail item is an accessibility element: label `"<name>, <state>"`, action press = switch, show-menu = context menu.
- Full keyboard operation. Respect Reduce Motion (no slide or fade animations) and Increase Contrast (ring widths).
- VoiceOver users: the Docked mode caveat in 4.2.6 / D-18 is documented in Help.

---

## 7. Architecture

### 7.0 Foundation rule

`claude-multiprofile` is the foundation (ruled 2026-09-29). Sidelauder re-implements none of its profile knowledge:

| Knowledge | Upstream owner (0.1.31, E27) | Sidelauder |
|---|---|---|
| Which profiles exist; their launchers, data folders and colours | `getRegistry`, `registryLocation` | Reads upstream's output |
| The default install | `detectDefaults` | Reads upstream's output |
| Where each profile's app copy is; whether it is stale or refreshing | `clonePathFor`, `launchTargetFor`, `cloneIsStale` | Reads upstream's output |
| Which running process belongs to which profile; strays | `runningCopies`, `dataDirInUse`, the helper's `onProfile` | Reads upstream's classification; checks only liveness at act time (§8.4) |
| Which profiles share an account | `desktopAccountUuid` (used by `doctor`) | Receives profile names only, never an account ID |
| Launching a profile, refreshing its copy, catching a wrong-account copy | The launcher and its helper | Opens the launcher |
| Windows, activation, hiding, the rail, hotkeys, its own preferences | — | **Sidelauder's own** |

**The interface.** Sidelauder reads profile knowledge from one read-only, offline, versioned command, `claude-multiprofile status --json` (§8.1), proposed upstream as U1 (§15). Until upstream ships it, Sidelauder bundles a thin adapter, `upstream-status.mjs`, that imports the installed package's exported functions (4.1.24) and prints the same JSON. The adapter composes upstream functions and adds four composition rules upstream draws inline but does not export, each named in its header (§8.1.3); it is deleted when U1 merges. D-20 covers a refusal.

**The hot path.** An upstream call costs 124 ms (median, S16; `--full` 281 ms), so it never runs inside a switch. Sidelauder caches upstream's last answer and re-queries on events that can change it (§8.1.4). At the moment of acting it checks only liveness: the PID upstream reported is alive with the same bundle and start time (§8.4).

### 7.1 Component view

```
┌──────────────────────────────── Sidelauder.app (agent, non-sandboxed, hardened runtime) ───────────────────────────────┐
│                                                                                                                         │
│  RailUI (SwiftUI + AppKit)          SwitchCoordinator (actor)            Placement (strategy)                          │
│  ├ RailPanelController      ───────▶ switchTo(profile, origin)  ───────▶ ├ FloatingPlacement  (Mode A: no AX)          │
│  ├ MenuBarExtra                     ├ coalescing, latest-wins            └ DockedPlacement    (Mode B: AX)             │
│  ├ Onboarding / Settings            ├ Solo/Stack policy                                                                 │
│  └ SignInAssistant                  └ Activator (ladder §9.7)            HotkeyService (Carbon RegisterEventHotKey)     │
│                                                                                                                         │
│  ProfileStore (upstream's last answer) ◀── UpstreamClient (runs the status command; decodes; version gate)              │
│      │                                 ◀── RefreshTriggers (NSWorkspace launch/terminate, wake, upstream config dir)   │
│      ▼                                                                                                                  │
│  ProfileState per profile (pure state machine §9.1)        Liveness (PID + bundle + start time; never argv)            │
│                                                                                                                         │
│  AXService (dedicated thread + run loop; messaging timeout) ── only for managed PIDs                                    │
│  WindowIndex (CGWindowList snapshots; no permission)                                                                    │
│  SafeFileStore (the only writer: ~/Library/Application Support/Sidelauder/, prefs, logs)                               │
│  Diagnostics (os.Logger + OSSignposter; redacted export)                                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
          │ runs, read-only                                   │ window-level AX / LaunchServices / NSRunningApplication
          ▼                                                   ▼
  claude-multiprofile status --json                   Claude instances (unmodified): /Applications/Claude.app, app copies
  (interim: bundled upstream-status.mjs,              launchers (~/Applications/Claude <Name>.app)
   calling upstream's exported functions)
```

### 7.2 Modules (local Swift package `SidelauderKit`)

| Module | Contents | Depends on | Testable on CI |
|---|---|---|---|
| `RailCore` | Pure logic: upstream status model and decoder (schema v1, version gate), state machine, Solo selection, slot and rail geometry (free-edge rule, make-room), hotkey map, settings model, `rail.json` codec. No AppKit | Foundation | ✅ `swift test` |
| `RailPlatform` | Adapters behind protocols: `UpstreamRunning` (spawn with timeout and allowlisted arguments), `Liveness`, `WorkspaceObserving`, `AXControlling`, `WindowListing`, `Launching`, `Activating`, `HotkeyRegistering`, `FileWatching` (trigger only), `SafeFileStoring` | AppKit, ApplicationServices, Carbon (HotKey only), ServiceManagement | Partly (non-AX) |
| `RailUI` | Views, panel controllers, onboarding, settings, menu bar | SwiftUI, AppKit, RailCore, RailPlatform | Snapshot tests optional |
| App target | `@main`, Info.plist, entitlements, assets, `upstream-status.mjs` (interim) | RailUI | Build only |
| `ProfileSource` (protocol in RailCore) | Seam for NG9 (other profile tools later); v1 has one conformer, `MultiprofileSource`, backed by `UpstreamClient` | — | ✅ |

**No bundled third-party code** `[D]`. Sidelauder requires `claude-multiprofile` installed, with the Node runtime it already needs; the interim adapter runs on that Node. Tooling-only dependencies (e.g., swift-format) stay out of the shipped binary.

### 7.3 Concurrency model

- `@MainActor`: UI, `ProfileStore` publication, `NSWorkspace` observation.
- `SwitchCoordinator` is an `actor`. Switches are serialized; a new request while one is in flight replaces the pending target (latest wins).
- `UpstreamClient` runs off the main actor: one call in flight, later triggers coalesced into one follow-up call, 3 s timeout (a cold call takes ~1.5 s, 4.1.20). Two kinds of call: the default one on process events, and `--full` at start and on an upstream config change (§8.1.4). A failed or timed-out call keeps the last good answer and marks it stale.
- `AXService` owns a dedicated thread with its own `CFRunLoop`. `AXObserver` sources are attached there. All AX calls are serialized on it, with `AXUIElementSetMessagingTimeout(app, 0.25)` `[K]`. Results are hopped to the main actor. A timed-out call counts as failure: the switch falls back to Mode A behaviour for that step.
- No polling timers at idle. Exceptions: the onboarding trust poll (only while visible) and the Mode A optional attached placement (not in v1).

### 7.4 Platform floor and toolchain

| Item | Choice `[D]` | Why |
|---|---|---|
| Minimum macOS | 26.0 (D-04, ruled) | The two versions the maintainer can test are 26 and 27. The cooperative-activation APIs exist since 14 (E26) |
| Architectures | Universal (arm64 + x86_64); Intel is built but untested, and the README says so | macOS 26 still runs on some Intel Macs `[K]`; no Intel test machine |
| Language | Swift 6, strict concurrency (Xcode 27 / Swift 6.4 on the first user's Mac, E28) | |
| Build | Thin checked-in Xcode project + local SwiftPM package holding all code (D-17) | `pbxproj` rarely changes, so contributor merges stay easy |
| Sandbox | **Off** | Runs the user's `claude-multiprofile`, opens launchers outside any container, controls other apps' windows through Accessibility |
| Hardened runtime | On; no exceptions requested | Library validation blocks dylib injection into our AX-privileged process `[K]` |
| Entitlements | None beyond hardened runtime defaults | No Apple Events needed: launching and activating use LaunchServices and `NSRunningApplication` |

---

## 8. Data and contracts

### 8.1 The upstream interface (Sidelauder's only read contract)

#### 8.1.1 Target: `claude-multiprofile status --json` (proposed as U1)

Read-only, offline (4.1.22), exit 0 with one JSON document on stdout. Schema v1, as Sidelauder needs it, and as the interim adapter prints it:

```json
{
  "schemaVersion": 1,
  "toolVersion": "0.1.31",
  "helperVersion": 1,
  "helperState": "current",
  "registry": { "path": "/Users/me/.config/claude-multiprofile/profiles.json", "health": "ok" },
  "default": { "present": true, "appPath": "/Applications/Claude.app", "dataDir": "/Users/me/Library/Application Support/Claude",
               "instances": [ { "pid": 501, "state": "onProfile", "appPath": "/Applications/Claude.app" } ],
               "sharesAccountWith": [] },
  "profiles": [
    { "name": "work", "displayName": "Work", "color": "teal",
      "launcher": { "path": "/Users/me/Applications/Claude Work.app", "present": true, "bundleId": "com.claude-multiprofile.work", "usesHelper": true },
      "app": { "path": "/Users/me/Library/Application Support/claude-multiprofile/apps/Claude work.app", "dedicated": true, "stale": false },
      "dataDir": "/Users/me/Library/Application Support/Claude-Work",
      "instances": [ { "pid": 502, "state": "onProfile", "appPath": "/Users/me/Library/Application Support/claude-multiprofile/apps/Claude work.app" } ],
      "sharesAccountWith": [] }
  ]
}
```

- `state` is one of `onProfile` · `stray` (the profile's app running without its data folder, or with one that no profile registers) · `foreignDataDir` (the profile's app running another registered profile's data folder; listed under the data folder's profile) · `sharedApp` (the profile's data folder running on a shared Claude.app: the default install, or the source app of a profile without its own copy). These are upstream's classifications, from the same `ps` matching its helper uses (4.1.9).
- Each instance carries the `appPath` it runs from, which is not always its profile's `app.path` (`foreignDataDir`, `sharedApp`). The liveness check compares against it (§8.4).
- A Claude process upstream does not classify is absent from the answer; Sidelauder treats any running `com.anthropic.claudefordesktop` process missing from it as unmanaged. (v0.2's `unmanagedInstances` is dropped: the adapter could only fill it with its own process matching.)
- Account IDs never appear: `sharesAccountWith` lists profile names only (`default` for the default install).
- `launcher.bundleId`, `launcher.usesHelper` and `app.stale` each cost a process per profile; the adapter reads them only with `--full` and prints `null` otherwise (§8.1.3).
- Paths are absolute; Sidelauder also accepts `~`-abbreviated ones.
- Proposed with U1, not in the interim adapter: `app.refreshing` (4.1.24) and `lastLaunch` per profile (time and outcome from the launch log), for the "why didn't it start?" popover.

#### 8.1.2 How Sidelauder calls it

- The absolute paths of `claude-multiprofile` and `node`, found once through the user's login shell at onboarding (§6.7), and the `XDG_CONFIG_HOME` that shell reported, if any.
- Arguments from an allowlist: `status --json` only. Interim: `node upstream-status.mjs <claude-multiprofile path> [--full]`; the adapter refuses any other shape. Never `upgrade`, `doctor` or any command that writes (GD-6).
- Environment: `PATH` = the found `node`'s directory + `/usr/bin:/bin`; `XDG_CONFIG_HOME` as found; nothing else inherited.
- One call in flight, 3 s timeout, stdout capped at 1 MB, stderr kept for diagnostics.

#### 8.1.3 Interim adapter (until U1 merges)

`App/Sidelauder/upstream-status.mjs` (built in M0, S16). It finds the installed package from the executable Sidelauder found, reads upstream's version through upstream's own `toolVersion` before importing anything else, then imports `src/registry.js`, `detect.js`, `appclone.js`, `desktop.js`, `launchhelper.js`, `state.js` and `util.js` by absolute path and prints schema v1. It composes upstream's exported functions (4.1.24) over one process snapshot taken by upstream's `psSnapshot`. Four rules upstream does not export are named in its header, each proposed for U1:

- **E1** `displayName` is the launcher's file name without `Claude ` and `.app` (4.1.19).
- **E2** A process of the default app whose command line carries a data folder that is neither a registered profile's nor the default one is left out, by `doctor`'s own test (`includes("--user-data-dir=")`).
- **E3** The four states compose `runningCopies` and `dataDirInUse`, drawing the line the helper and `doctor` draw inline.
- **E4** Because `runningCopies` matches by substring (4.1.26), app paths are scanned longest first and each process is reported once. An unregistered Claude whose path ends in a scanned one is still reported under it; the liveness check discards it on the bundle URL (§8.4).

Account grouping calls upstream's `desktopAccountUuid`, which reads `config.json` inside the data folder. That read happens in upstream's code, in the Node process the adapter runs in; the adapter prints profile names only. Sidelauder's own process never opens the file (I3).

**Cost** (S16, E32): 124 ms median end to end, p95 128 ms; `--full` 281 ms. Node's start (~93 ms) and one `ps` (~50 ms) are most of it. `--full` adds, per profile, a `PlistBuddy` read of the launcher's bundle ID, a decompile of its script to see whether it uses the helper (~50 ms), and two version reads for staleness.

**Versions.** The adapter is pinned to the upstream versions it was tested against (`TESTED_VERSIONS`, 0.1.31 today, re-tested per upstream release). Any other version gets, on stdout, `{"schemaVersion":1,"error":{"kind":"untestedVersion","toolVersion":"…"}}` and exit 3, which the app shows as "Upstream unavailable: untested version N" rather than a guess. It couples Sidelauder to upstream internals, which is why U1 is on the critical path.

**Checks.** Three gates hold it: 28 composition tests on a fake upstream plus the static GD-10 clause; 7 tests through the installed upstream in a throwaway home folder (every state, paths with spaces, quotes and accents, shared accounts, a corrupt registry, nothing written); and 11 mutations, each of which must turn a test red (§13.3).

#### 8.1.4 When Sidelauder re-queries

`--full`: at start; on a change in upstream's config directory (a `DispatchSource` used as a trigger only, debounced 300 ms; Sidelauder never parses the file); on user request.

The default call: on `NSWorkspace` launch and terminate of any app with bundle ID `com.anthropic.claudefordesktop`; on wake; after any launch it starts, until the new instance is classified or 45 s pass; after a failed liveness check (§8.4).

#### 8.1.5 Tolerance

| Case | Behaviour |
|---|---|
| `schemaVersion` = 1 | Use |
| `schemaVersion` > 1, missing, or not an int | "Upstream unavailable: unsupported schema"; no launches or switches |
| Exit 3 with `error.kind` = `untestedVersion` | "Upstream unavailable: untested version N"; no launches or switches |
| Unknown fields; `null` for a `--full` field | Ignored; the last `--full` value is kept |
| A profile without `launcher` or `app`, or with `launcher.present` false | That profile is Unavailable, with upstream's reason when given |
| Any other non-zero exit, timeout, invalid JSON, oversize output | Keep the last good answer, greyed; banner; retry on the next trigger |

### 8.2 Default profile

Comes from upstream's `default` block (4.1.23). Display name "Default", renamable in `rail.json`. Launch = open `default.appPath` (§9.6).

### 8.3 Sidelauder's own state (`~/Library/Application Support/Sidelauder/rail.json`)

```json
{
  "version": 1,
  "order": ["default", "work", "client"],
  "profiles": {
    "work":   { "nickname": "Work", "avatar": { "kind": "initials", "text": "W", "color": "#3B82F6" }, "keepVisible": false, "hiddenFromRail": false },
    "client": { "keepVisible": true }
  },
  "slots": {
    "<displaySignature>": { "x": 120, "y": 80, "w": 1280, "h": 860, "screen": "<displayUUID>" }
  }
}
```

- Keys are upstream profile names; `default` is the Default profile.
- Coordinates are stored in AX/CG global top-left space (§9.9).
- `displaySignature` = SHA-256 of the sorted `(CGDisplayCreateUUIDFromDisplayID, frame)` list, so slots are remembered per monitor arrangement.
- Writes go through `SafeFileStore` only: write to a temp file, then `rename`, keeping a `rail.json.bak`. A corrupt file → restore from `.bak`, else defaults, and log.
- UI preferences that are not per-profile, and the found upstream paths, live in `UserDefaults` (app domain).
- A profile renamed upstream starts with fresh rail settings. `rename` moves the data folder, the app copy and the launcher's bundle ID together (4.1.21), so nothing stable is left to match. Documented.
- Appendix B has the JSON Schema.

### 8.4 Acting on the right process (heart of GD-1)

Upstream classifies; Sidelauder only verifies that a process is still the one upstream classified.

1. **On each upstream answer**, for every reported PID: `NSRunningApplication(processIdentifier:)` must exist, with bundle ID `com.anthropic.claudefordesktop`, `activationPolicy == .regular`, and a `bundleURL` equal to the instance's reported `appPath` (paths standardized; compared case-insensitively where the volume is, `URLResourceValues.volumeSupportsCaseSensitiveNames`). Sidelauder records the process start time (`sysctl(KERN_PROC_PID)`, 4.2.14). A mismatch discards that PID and triggers one re-query. This is also what catches the adapter's one known misattribution (§8.1.3, E4).
2. **At the moment of acting** (activate, hide, unhide, set frame, quit), the PID must be alive with the same bundle URL and start time as recorded. Otherwise Sidelauder re-queries once; if the profile then has no live on-profile instance, the switch becomes a launch through the launcher.
3. Sidelauder never reads argv and never decides which profile a process belongs to.

**Pre-open checks (GD-7, D-16).** These are sanity checks against misconfiguration, not a defence against a local attacker, which is out of scope as in upstream's SECURITY.md (E6):
1. Before opening a **launcher**: its path equals upstream's `launcher.path`, and its `CFBundleIdentifier` starts with `com.claude-multiprofile.` (4.1.14).
2. Before opening the **Default app**: `SecStaticCodeCheckValidity` (default flags, not strict; see 4.1.4) passes and the bundle identifier is `com.anthropic.claudefordesktop`.
3. A failure → Unavailable with the reason.

### 8.5 Account duplicates

Upstream's (4.1.12). Sidelauder receives `sharesAccountWith` (profile names) and shows Duplicate account on each named profile. Its own code opens no file in any Claude data folder and never holds an account ID (I3).

### 8.6 Upstream files

Sidelauder reads none directly. What v0.1 read (`<clone>.refreshing`, the `launch.log` tail, the helper version) comes through the interface: `app.refreshing`, `helperVersion` and the proposed `lastLaunch`. A data folder's path is only ever handed to Finder, by "Reveal data folder".

---

## 9. Behaviour specification

### 9.1 Per-profile state machine (pure, in `RailCore`)

Profile state is a product of orthogonal facets. The primary lifecycle:

| State | Enter on | Exit on |
|---|---|---|
| `notRunning` | No resolved instance | Launch requested → `starting` · external launch detected → `running` |
| `starting(since, via)` | Launch requested (launcher, or the Default app) | Upstream classifies the new instance → `running` or `stray` · 45 s timeout → `startStalled` · launcher process exits with no instance after 45 s → `startStalled` |
| `startStalled` | Timeout | Instance appears → `running` · user retries → `starting` · dismiss → `notRunning` |
| `running(pid)` | Upstream reports the instance `onProfile`, `foreignDataDir` or `sharedApp`, and it passes liveness | Terminate notification → `notRunning` · liveness fails → re-query |
| `stray(pid)` | Upstream reports `stray` | Terminate → `notRunning` · user Reopen → `reopening` |
| `reopening` | User confirmed Reopen | Launcher's helper handles quit+reopen; → `running` or `stray` (user declined in the helper's dialog) |

**Facets on `running`:** `hidden: Bool`, `frontmost: Bool`, `hasStandardWindow: Bool` (B), `fullScreen: Bool` (B), `onActiveSpace: Bool` (B).

**Cross-profile facets:** `duplicateAccount(with: Set<ProfileID>)` (from upstream), `unavailable(reason)`, and the rail-wide `upstreamUnavailable(reason)`.

The transition function is total and table-tested (every state × every event).

### 9.2 Switch algorithm (common core)

```
switchTo(P, origin ∈ {railClick, hotkey, menu, external}):
  coalesce(P)                                     # latest wins while a switch is in flight
  src := frontmostManagedInstance()               # may be nil
  inst := store.liveInstance(P)                   # upstream's last answer + liveness (§8.4); one re-query on failure
  match inst:
    nil                  → return launch(P, placement.slotFor(src))            # §9.6
    stray                → return offerReopen(P)                               # §6.2
    running where P == src.profile
                         → placement.resnap(inst); return                      # B only
  placement.prepare(src, inst)                    # A: no-op; B: §9.4
  ok := activator.activate(inst, origin)          # §9.7; ok only once didActivateApplication arrives for inst.pid
  if !ok: rail.flash(P, "Couldn't bring it forward — click its window"); log; return
                                                  # nothing is hidden without a confirmed target
  if policy == .solo:
      for other in visibleManagedInstances() where other ≠ inst and !other.profile.keepVisible:
          if liveness.holds(other): hider.hide(other); markHiddenByUs(other)   # §9.8
  rail.reposition()
  signpost.end(switch)
```

### 9.3 Mode A specifics

- `FloatingPlacement.prepare` is a no-op. `slotFor` returns nil.
- `rail.reposition` = the free-edge rule of §6.3 against the target's frontmost on-screen window (CGWindowList by PID), falling back to `NSScreen.main`.

### 9.4 Mode B: slot handoff (M1a)

```
DockedPlacement.prepare(src, dst):
  guard ax.trusted else → return .fallbackA(reason: .noPermission)
  guard !dst.profile.keepVisible else → return .none
  slot := src.flatMap(ax.mainStandardWindowFrame) ?? savedSlot(displaySignature) ?? nil
  guard let slot else → return .none                      # first ever switch: adopt dst's own frame as the slot
  if src?.fullScreen == true or dst.fullScreen == true → return .fallbackA(.fullScreen)
  w := ax.mainStandardWindow(dst)                         # reachable while hidden (S3: 50/50)
  if w == nil and dst.hidden: hider.unhide(dst); w := await ax.waitForMainStandardWindow(dst, timeout: 800 ms)
  guard let w else → return .fallbackA(.noWindow)
  if !windowIndex.isOnActiveSpace(w.cgWindowID) → return .fallbackA(.otherSpace)
  if w.minimized: ax.set(w, .minimized, false)
  withEnhancedUIDisabledIfOn(dst):                        # D-18; restores the prior value; never sets true (GD-5)
      ax.setFrame(w, slot)                                # size → position → size (E19); while still hidden (D-22)
  if dst.hidden: hider.unhide(dst)                        # no activation yet
  actual := ax.frame(w)
  if !actual.approximatelyEquals(slot, tolerance: 1 pt):  # e.g., below Claude's 600 × 400 pt minimum (4.2.4)
      slot := actual; persistSlot(slot)                   # adopt reality; re-glue the rail
  return .placed(slot)
```

**Launch-into-slot (F-B3).** After the launcher starts the instance, wait for `kAXWindowCreatedNotification` or the first standard window (up to 45 s, because the helper may be refreshing the copy), then `setFrame(slot)`, then activate. Electron restores its own last bounds first, so a visible jump is expected. S6 measures it; the mitigation is to set the frame on the first AX window-created event.

**Slot updates.** An AX moved or resized notification on the active window → `slot := frame`, persisted (debounced 500 ms), and the rail follows (§9.5).

**Make room (F-B4).** Evaluate on every slot update. If the rail does not fit on the leading side, shift the window, shrinking its width if needed; the resulting frame becomes the slot.

**Ordering (S3, D-22).** Variant 2, adopted: set the frame while the target is still hidden → unhide + activate → hide the source. Variant 1 (unhide → set frame → activate → hide the source) showed the target outside the slot for 1–2 frames in 8 of 20 relocations; variant 2 in none of 50 switches. Both land within 1 pt (100/100) and take 50–65 ms median from click to source hidden. Both show 2 to 4 in-between frames inside the slot when the window must change size (about 35–65 ms), most likely Claude redrawing at its new size; whether that is visible is the operator's call on the real rail, an M1a exit criterion (E32, S3).

### 9.5 Mode B: attached rail tracking (M1b)

- Observed per managed PID: `kAXApplicationActivatedNotification`, `kAXApplicationHiddenNotification`, `kAXApplicationShownNotification`, `kAXFocusedWindowChangedNotification`, `kAXMainWindowChangedNotification`, `kAXWindowCreatedNotification`.
- Observed on the active window: `kAXMovedNotification`, `kAXResizedNotification`, `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification`, `kAXUIElementDestroyedNotification` `[K]`.
- Rail frame (AppKit coordinates) = `(win.minX − railWidth, win.minY, railWidth, win.height)`; mirrored for the trailing side.
- Coalesce moves to the display link (`NSView.displayLink`, macOS 14). If Electron emits moved notifications only at the end of a drag (S4), the rail hides during the drag (it is re-shown on mouse-up via a global `leftMouseUp` monitor, which needs no permission) rather than lagging visibly.
- Show the attached rail iff the frontmost app is a managed instance that is not kept visible (on-profile, not full screen, on the active Space) or Sidelauder itself. Otherwise `orderOut`.

### 9.6 Launch

| Profile kind | Launch action | Notes |
|---|---|---|
| Registry profile | `NSWorkspace.openApplication(at: launcher.path)` after the §8.4 launcher check, and only once no modifier key is held (below) | The helper may refresh the copy and may show its own dialog (4.1.8); Sidelauder shows `starting` |
| Default | `openApplication(at: default.appPath, configuration: { createsNewApplicationInstance: X })`, with X = true iff upstream reports a `sharedApp` instance on that app (a legacy shared-bundle profile), matching upstream's `-n` reasoning (E2) | Signature check first (D-16) |

Any launch waits for `didLaunchApplication` plus an upstream answer that classifies the new instance. An instance that vanishes mid-switch is never relaunched directly: the switch re-enters as a launch through the launcher (§5.4).

**Never open a launcher with a modifier held.** A launcher opened while Control is down stops at its startup screen and launches nothing (4.1.27), and a hotkey leaves Control down at the moment it fires. Before opening any launcher (a launch, or ladder step 2), Sidelauder polls `CGEventSource.flagsState(.combinedSessionState)` until Control, Option, Shift and Command are all released, for up to 2 s; if they are still held, the rail shows "Release the keys to open <profile>" and opens on release. Guarded like the others (GD-7 gains the partition "modifier held").

### 9.7 Activation ladder (public APIs only, I10)

| Step | Condition | Call | Success check |
|---|---|---|---|
| 0 | Origin is a hotkey or the menu bar, and Sidelauder is not active | `NSApp.activate()` for Sidelauder itself, on the strength of the user's input `[V]` A17 on synthetic input (S1) | `didActivateApplication` for Sidelauder within 100 ms → continue at step 1 |
| 1 | Sidelauder is active (a rail click activates it, or step 0 succeeded) | `NSApp.yieldActivation(to: target)` then `target.activate(from: .current, options: [])` `[V]` E26 | `didActivateApplication` for the target PID within 300 ms |
| 2 | Step 1 not applicable or failed | Open the profile's **launcher**, once no modifier is held (§9.6): upstream's documented launch-or-focus (4.1.2: `open -a` on the app copy focuses a running instance). Default: open `default.appPath`, only when it is the sole instance of that app `[V]` A5 (S1) | Same, within 1.5 s (the helper runs first) |
| 3 | Accessibility is trusted | Set `kAXFrontmostAttribute = true` on the target's app element, then `AXRaise` on its main window. Ineffective on an instance just hidden and unhidden (4.2.21) | Same |
| 4 | All failed | Flash the rail item; toast "Click its window to focus"; log with cause | — |

**Measured (S1, macOS 27, 50 trials each, E32).** From an app without Accessibility, on synthetic input:

| Route | Target in front | Window in front, p50 / p95 |
|---|---|---|
| Rail click → step 1 | 139/139 (incl. 89 right after typing in the front app) | 36–39 / 45–55 ms |
| Hotkey → step 0 → step 1 | 100/100; step 0 alone 100/100, p95 15 ms | 38 / 45 ms |
| Step 1 or a plain `activate`, no input to Sidelauder | 199/199 (100 right after typing in the front app) | 30–32 / 34–36 ms |
| Step 2 (launcher) | 50/50 | 349 / 434 ms |
| Step 3 (granted harness) | 100/100 | 25–29 / 30–32 ms |

Nothing was refused, not even the call cooperative activation exists to refuse, so these runs show the ladder works when nothing resists it. The operator's real-input check then typed in one profile and switched with the real hotkey (18/18, 42 / 51 ms to the window) or a real rail click (12/12, 31 / 35 ms): nothing was refused there either (R1). `activate(from:options:)` returned true every time, so success stays defined by the notification. Step 2 always showed the previously active profile again for about 150 ms, between the launcher quitting and the target arriving: it stays a fallback. The macOS 26 runs move to M2. v0.2's idea of opening the app copy directly ahead of step 2 is dropped: step 1 met the targets.

### 9.8 Hide and unhide

- `NSRunningApplication.hide()` / `.unhide()`: the header promises only that the request was sent (E26). From a non-active app without Accessibility both worked 50/50 on macOS 27, confirmed in 3 ms (hide) and 2 ms (unhide) median, and never moved activation (S2, E32). Both returned false every time (4.2.20): a hide or unhide is confirmed by its notification and `isHidden`, never by the return value. macOS 26 at M2.
- Solo hides only after the target's activation is confirmed (§9.2).
- Record in memory the PIDs **hidden by Sidelauder**. On Sidelauder quit (D-15), unhide exactly those. Never unhide instances the user hid.
- Never minimize as a substitute for hide: minimizing animates and fills the Dock.

### 9.9 Geometry

- **Spaces:** AX, CGWindowList and `rail.json` slots use global top-left coordinates; AppKit uses bottom-left.
- **Conversion** (single function, unit-tested with multi-display fixtures, including displays above and left of the primary): `appKitY = primaryScreen.frame.maxY − (axY + height)`, where `primaryScreen = NSScreen.screens[0]` (the menu-bar screen at its origin) `[K]`.
- **Clamping:** a slot restored onto a changed display arrangement is intersected with the target screen's `visibleFrame`. If less than 50 % survives, re-centre at the slot's size, shrunk to fit but never below Claude's 600 × 400 pt minimum (4.2.4).
- **Rounding:** integral points, to avoid AX jitter loops (set → notification → set).
- **Feedback-loop guard:** ignore moved or resized notifications for 150 ms after our own `setFrame` on that window.

### 9.10 Edge cases

| Case | Behaviour |
|---|---|
| Source or target full screen | No handoff; rail hidden over full screen; activation still works (Mode A behaviour) |
| Target window on another Space | Activation may switch Space (system setting); no handoff; toast once |
| Stage Manager on | Detect via `UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled")` `[A]`. Docked mode allowed with a warning; S9 decides whether to force A |
| Target has several windows | Use `kAXMainWindowAttribute` if it has subrole `AXStandardWindow`; else the first standard window. Ignore dialogs and floating panels (Quick Entry etc.) |
| Target minimized | Deminimize via AX (B); in A, activation deminimizes per system behaviour `[K]` |
| Window closed, app still running | `hasStandardWindow = false`. Click → activate (Claude typically reopens a window `[A]`); B adopts the new window into the slot on `kAXWindowCreatedNotification` |
| Instance quits or crashes | `notRunning`; if it was active, the rail stays over the last slot for 2 s and then hides |
| Clone refresh in progress | `starting` with "Updating Claude copy…"; clicks coalesced |
| `self-update on` profile relaunches without the flag | Upstream reports `stray`; amber; Reopen routes through the launcher |
| Two profiles on the same account | Upstream reports it → Duplicate account → sign-in assistant |
| Notification click from a hidden profile | The clicked instance activates (which one is S15's question); the rail follows; Mode B applies D-07 |
| A hidden profile is mid-response or running a Code task | Keeps running: a hidden chat answer finished no later than a visible one (S14, 4.2.17). Hides over 5 minutes and Code tasks are checked at M1a; if either stalls, Solo gains a rule not to hide a busy instance (D-06) |
| A hidden profile waits for a Code approval | It waits until shown (4.2.23). Sidelauder cannot see the prompt (I6); a documented limit of Solo. Keep visible (per profile) is the workaround for approval-heavy sessions |
| Display unplugged or rearranged | `didChangeScreenParametersNotification` → re-clamp slot, reposition rail |
| Sleep / wake | `didWakeNotification` → re-query upstream (PIDs may have changed) and re-validate AX observers |
| AX call times out (instance busy) | That step fails fast (0.25 s); the switch continues with the next ladder step or the Mode A fallback |
| Accessibility revoked mid-session | Detected on the next AX error → Mode A + banner |
| Registry corrupt; `claude-multiprofile` missing, failing or too new | Upstream unavailable: keep the last good answer greyed, banner, no launches or switches, never write |
| Profile renamed upstream | Shows as a new profile with fresh rail settings (§8.3; 4.1.21) |
| User runs VoiceOver (enhanced UI on in Claude) | D-18 transient disable around `setFrame`; documented |
| Another window manager (Rectangle, AeroSpace) also moves Claude | Last writer wins; document the conflict; the feedback-loop guard prevents ping-pong |
| Quick Entry global shortcut across instances | Out of Sidelauder's control (a multi-instance limitation); documented |
| Fast User Switching | Per-session; nothing special |

### 9.11 Sign-in assistant (F-C8)

This automates upstream's own first-launch checklist (E1) without touching the sign-in flow (4.3.1).

1. Explain why: sign-in links reach whichever Claude answers. List the other running instances.
2. Ask to quit them. Use `terminate()` (polite) for each and wait up to 20 s each. If one refuses (unsaved state), show it and let the user handle it. Never force (I7).
3. Launch the target profile through its launcher.
4. The user signs in in their browser through Anthropic's flow. Sidelauder just waits, with a "Done" button.
5. Verify: re-query upstream and report whether the profile still shares an account with any other (§8.5).
6. Offer to reopen the instances quit in step 2, through their launchers.

### 9.12 Badges

Not in v1 (NG5). The Dock route (4.2.10) and the question of whether Claude sets a badge at all (v0.1's S8) move to the backlog (§16.4).

---

## 10. Security and privacy

### 10.1 Assets, actors, trust boundaries

| Asset | Where | Sidelauder's access |
|---|---|---|
| Claude sessions and conversations | Inside Claude processes and servers | None |
| Credentials and tokens | Claude data folders, Keychain | None (I2, I3) |
| Account ID | `config.json` in each data folder, beside the encrypted sign-in cache (4.1.25) | None. Upstream compares; Sidelauder receives profile names only |
| Upstream's profile knowledge | `claude-multiprofile` | Read-only output of one allowlisted command |
| Window control capability | Sidelauder's Accessibility grant | Held by Sidelauder; scoped by GD-4 |
| Profile layout | Registry (upstream) | Read-only |

**Threats:**

| Threat | Mitigation |
|---|---|
| T1: Malicious or compromised Sidelauder release (an AX-privileged binary is keylogger-grade) | Zero runtime dependencies; Developer ID signing + notarization; release from CI with a pinned toolchain; SHA-256 sums; signed tags (on approval); reproducible-build notes; minimal code surface |
| T2: Dylib injection into Sidelauder to borrow its grant | Hardened runtime with library validation `[K]`; no `DYLD` exceptions |
| T3: Confused deputy via a tampered registry or upstream output (open a non-Claude app) | §8.4 sanity checks (launcher path equals upstream's, bundle-ID prefix; Default signature valid). They catch misconfiguration, not an attacker: anyone who can write the registry can write `~/Applications`. Local code execution as the user is out of scope, mirroring upstream's SECURITY.md (E6) |
| T4: Acting on the wrong process (PID reuse, lookalike bundle) | GD-1: upstream's classification plus the act-time liveness check (PID, bundle URL, start time) |
| T5: Leaking data via logs or diagnostics | Paths logged as `.private`; no account ID ever held; no window titles or content ever read |
| T6: Crossing profile isolation | Sidelauder never moves data between profiles; the sign-in assistant only quits and launches |
| T7: Running a substituted `claude-multiprofile` or `node` | Paths found once through the user's login shell and confirmed by the user; allowlisted arguments; 3 s timeout; output size cap. A `PATH` an attacker controls is local code execution, out of scope |

### 10.2 What Sidelauder reads, runs, writes, never does

| Reads | Runs | Writes | Never |
|---|---|---|---|
| The output of `claude-multiprofile status --json` (or the interim adapter); launcher `Info.plist` (bundle ID); the Default app's `Info.plist` and code signature; liveness of same-user `com.anthropic.claudefordesktop` processes (PID, bundle URL, start time; never argv); CGWindowList bounds; window-level AX of managed PIDs | `claude-multiprofile status --json` (interim: `node upstream-status.mjs <path> [--full]`, which runs upstream's own functions, §8.1.3); the user's login shell once, at onboarding, to find them | `~/Library/Application Support/Sidelauder/` (`rail.json`, `.bak`); its `UserDefaults` domain; unified logging; a login item only if the user enables it | Everything in §2.3: Claude bundles, any file inside a Claude data folder, the Keychain, tokens, account IDs, upstream's files, the `claude://` scheme, injection, debug ports, input synthesis, force-quit, network, private APIs, upstream commands that write |

### 10.3 Security deliverables

- `SECURITY.md` mirrors upstream's structure (E6): supported versions, private reporting via GitHub advisories, what counts, reach limits.
- A threat-model section in `docs/`.
- Each release notes any change to §10.2.

---

## 11. Policy compliance checklist (gate: the repository's first public commit, then every release)

| # | Check | Source |
|---|---|---|
| P1 | Product name, app icon and menu bar glyph contain no Claude or Anthropic name or logo (D-01, settled before the repository exists) | E23, E25 |
| P2 | README and site use referential plain text only; carry the "unofficial, not affiliated" disclaimer | E23, E25 |
| P3 | No tinted or altered Claude icons in marketing assets or screenshots (initials avatars) | E25 |
| P4 | No claim or feature about pooling usage limits | E23 |
| P5 | Static proof that Sidelauder's code opens nothing inside a Claude data folder, holds no credential, token or account ID, touches no Keychain, and registers no `claude://` handler (GD-2, GD-9, GD-10) | E23 |
| P6 | No automation of Claude's UI or traffic (GD-4, I6) | E24 |
| P7 | Decide whether to ask Anthropic before launch (D-01) | E25 |

---

## 12. Non-functional requirements

| Area | Target `[D]` (validated in M0) |
|---|---|
| Switch latency, running target, click → target key window | p50 ≤ 120 ms, p95 ≤ 250 ms (A); p50 ≤ 180 ms, p95 ≤ 350 ms (B). S3 also records time to the target's first fresh frame |
| Upstream answer | ≤ 200 ms warm for the default call, never on the switch path; a cold call (~1.5 s, 4.1.20) delays status only. Measured 124 ms median, 128 ms p95 (S16). `--full` (281 ms) runs only at start and on a config change |
| Hotkey switch latency | Same targets. Measured 38 ms median, 45 ms p95 to the target's window on synthetic input, and 42 / 51 ms on real input (S1) |
| Rail follow lag during drag (B) | ≤ 1 frame at 60 Hz where Electron streams moves; otherwise hide during the drag (§9.5) |
| Idle CPU | ≤ 0.1 % averaged over 10 min, 3 profiles running, no interaction |
| Memory | ≤ 60 MB RSS |
| Cold start → rail ready | ≤ 500 ms |
| Energy | No timers at idle (§7.3); App Nap allowed when the rail is hidden |
| Claude side-effects (S7) | No measurable change in Claude CPU (±2 %) or memory (±3 %) with Sidelauder observing vs not, 10-min run |
| Reliability | 0 wrong-process actions in the GD-1 suite; 500-switch soak with no stuck-hidden instances |
| Compatibility | macOS 26.x and 27.x on Apple silicon (Intel built, untested); Claude Desktop current plus previous release at test time; `claude-multiprofile` 0.1.31 onward |

---

## 13. Verification strategy

### 13.1 Test layers

| Layer | What | Where it runs |
|---|---|---|
| Adapter (built in M0) | `Tests/Adapter/`: 28 composition tests on a fake upstream, the static GD-10 clause, 7 tests through the installed upstream in a throwaway home folder, and 11 mutations each of which must turn a test red (§8.1.3) | Gates `adapter-unit` (anywhere with Node), `adapter-upstream` and `adapter-mutations` (the maintainer's Mac, where upstream is installed) |
| Unit (`RailCore`) | Upstream status decoding (fixtures: schema v1 from the adapter, and from the real command once it exists; missing fields; unknown schema; invalid JSON; oversize; timeout); liveness (§8.4); state machine (all state × event); Solo selection; geometry (conversion, clamping, free-edge rule, make-room, multi-display); hotkey map; `rail.json` codec | CI (`swift test`) |
| Integration, no AX | With `FakeClaude.app` and a fake upstream command: launch via fake launchers; liveness on real processes, including PID reuse; activation steps 0–2; hide/unhide; refresh triggers. Adapter tests run against the installed upstream on the maintainer's Mac | CI macOS runner (if a GUI session is available, `[A]` A13), plus local |
| Integration, AX | Frame handoff, attached rail tracking (M1b), enhanced-UI guard | Local dev Mac (TCC grant); CI only if S12 passes |
| Manual matrix | macOS 27 (M1a/M1b), then 26 and 27 (M2) × 1–2 displays × Stage Manager on/off × full screen × Spaces × real Claude Desktop | Pre-release checklist |
| Soak | 500 scripted switches across 3 profiles, both modes | Local, pre-release |
| Performance | `OSSignposter` intervals per switch; Instruments template checked in | Local, M0 and pre-release |

### 13.2 `FakeClaude.app` fixture

A tiny AppKit app built by the test target. Its bundle ID is injectable; the liveness check takes the "Claude bundle ID" as configuration, with the production value `com.anthropic.claudefordesktop`. Behaviour is controlled by environment variables:
- window count and minimum size;
- `AXEnhancedUserInterface` initially on or off;
- AX delay (simulate a busy app);
- quit refusal (simulate unsaved state).

Fake launchers are shell-script `.app` bundles with the `com.claude-multiprofile.` bundle-ID prefix, which open the fixture with `--user-data-dir`. A fake `claude-multiprofile` (a script printing fixture JSON, with delay, exit-code and garbage modes) stands in for upstream.

### 13.3 Guards: partitions, paired controls, red mutations

Each guard gets:
- tests over its **partitioned input domain**, driven through the **real entry point** (`SwitchCoordinator.switchTo` or the relevant service), not an internal helper;
- a **paired positive control** proving the action does happen in the valid case;
- a **mutation** that disables the guard. That mutation must turn at least one test red, and CI records each mutation's result separately (a script applies each mutation in turn).

| Guard | Protects | Input partitions (min.) | Positive control | Red mutation |
|---|---|---|---|---|
| GD-1 Right process | I11 | Upstream state (`onProfile` / `stray` / `foreignDataDir` / `sharedApp` / absent) × liveness (alive and same / gone / PID reused with a new start time / bundle URL differs from the reported path) × paths with spaces, quotes, unicode and case variants × upstream answer (fresh / stale after a launch event / failed) | `onProfile` + live → action issued to that PID | Skip the start-time comparison → the PID-reuse test goes red; treat `stray` as `onProfile` → red; act on a stale answer without the re-query → red |
| GD-2 Write confinement | I1–I3 | Writes to: own dir (allowed), a Claude data dir, a clone, the registry, `~/.claude`, `/tmp`, a symlink out of the own dir | `rail.json` save succeeds | Remove the allowlist check in `SafeFileStore` → the denial tests go red. Plus a static check: no `FileManager` / `Data.write` outside `SafeFileStore`, no `SecItem*` symbols |
| GD-3 Quit | I7 | Quit from: context menu confirmed / cancelled, sign-in assistant confirmed / cancelled, app termination | Confirmed → `terminate()` called once | Bypass the confirmation → the cancelled test goes red. Static: any `forceTerminate` fails CI |
| GD-4 AX scope | I6 | AX element creation for: managed PID, unmanaged Claude PID, non-Claude PID, the Dock | Managed PID → observer attached | Drop the PID filter → the unmanaged, non-Claude and Dock tests go red. Static: no `AXUIElementPerformAction` except `kAXRaiseAction`; no `CGEvent` post APIs |
| GD-5 Enhanced UI | I8 | Initial `AXEnhancedUserInterface`: true / false / unsupported; `setFrame` success / failure / timeout | True → set false, then restored to true | Remove the restore → the test goes red; a write of `true` when the initial value was false → red. Static: no `AXManualAccessibility` string |
| GD-6 Network and commands | I9 | `UpstreamClient` arguments: `status --json` (allowed), `upgrade`, `doctor --fix`, `add`, arbitrary strings | `status --json` runs | Allow any argument → the `upgrade` test goes red. Static: no `URLSession`, `Network.framework`, `NSURLConnection`, `CFSocket`, `getaddrinfo` imports or symbols in the linked binary (`nm`) → any hit fails CI |
| GD-7 Launch path | I5, I12 | Registry profile (launcher OK / wrong bundle ID / missing / path differs from upstream's), Default (signature valid / invalid), modifier keys (none held / held then released within 2 s / still held after 2 s) | Launcher OK, no modifier held → `openApplication(launcher)` | Skip the bundle-ID check → the wrong-ID test goes red; skip the path comparison → red; skip the modifier wait → the "held" test goes red. Static: no `--remote-debugging-port`, `--inspect` or `--user-data-dir` strings in Sidelauder's Swift sources (no direct app-copy launch) |
| GD-8 Private APIs | I10 | — (static) | — | Static: no `dlopen`/`dlsym`; no symbols matching `SLPS|CGS|_AX.*Private`; `nm -u` allowlist diff |
| GD-9 URL scheme | I4 | — (static) | — | Static: Info.plist has no `CFBundleURLTypes` entry for `claude`; no `LSSetDefaultHandlerForURLScheme` |
| GD-10 Foundation | I3, I14 | — (static) | — | Static: Sidelauder's Swift sources contain no `profiles.json`, `lastKnownAccountUuid`, `config.json`, `claude-multiprofile/apps` or `Application Support/Claude` literal and no `ps` invocation; `UpstreamClient` is the only upstream contact. The adapter contains no `ps` call, path literal or regular expression of its own; its imports are upstream's. Adding a direct read of `profiles.json` → red |

### 13.4 What CI runs (per PR)

1. `swift test` (RailCore), and `node --test` for the adapter's unit and GD-10 tests (the upstream and mutation gates need the installed upstream and run on the maintainer's Mac, through `review.toml`).
2. `xcodebuild` build (universal).
3. Non-AX integration tests (if A13 holds).
4. Static guards GD-2…GD-10.
5. Mutation runner for GD-1…GD-7 (runs in the unit layer where possible).
6. `swift-format` / lint (tooling-only dependency).

---

## 14. Build, release, distribution

### 14.1 Repository layout

```
sidelauder/                           # D-01
├─ README.md  LICENSE (MIT, D-12)  SECURITY.md  CHANGELOG.md  CONTRIBUTING.md
├─ App/Sidelauder.xcodeproj          # thin: app target + test host only
├─ App/Sidelauder/                    # Info.plist, entitlements, Assets (own icon), main.swift, upstream-status.mjs (interim, §8.1.3)
├─ Packages/SidelauderKit/
│  ├─ Package.swift
│  ├─ Sources/RailCore/  Sources/RailPlatform/  Sources/RailUI/
│  └─ Tests/RailCoreTests/  Tests/RailPlatformTests/  Tests/Mutations/
├─ Tests/Adapter/                     # the interim adapter's unit, upstream and mutation tests (M0)
├─ Fixtures/FakeClaude/  Fixtures/FakeLauncher/  Fixtures/FakeUpstream/
├─ scripts/  (guards.sh, mutate.sh, release.sh, notarize.sh)
├─ spikes/                            # M0 harnesses: Discovery, SpikeRunner/SpikeSubject, recording analysis (throwaway)
├─ docs/  (this spec, spikes/ (M0 reports), ADRs: 0001-no-private-apis, 0002-no-network, 0003-separate-repo, 0004-upstream-foundation, …)
├─ review.toml  AGENTS.md  CLAUDE.md → AGENTS.md    # loupe review configuration; agent instructions
└─ .github/workflows/ci.yml  release.yml
```

### 14.2 Phases

The repository is public from its first commit (D-02). Before it is created, the name is settled (D-01) and the first commit already satisfies §11 P1–P3: the name, the "unofficial, not affiliated" disclaimer, no Claude marks.

| Phase | Audience | Signing | Distribution | Gate |
|---|---|---|---|---|
| 0: Personal | First user | A stable local identity (Apple Development cert from a free Apple ID, or a self-signed code-signing cert), so the Accessibility grant survives rebuilds (4.2.11; S11). Signed that way from the first build: a grant recorded for an ad-hoc build does not carry over | Built from the public repository's source on the first user's Mac | M1a exit |
| 1: First release (beta) | Early OSS users | Developer ID Application (Apple Developer Program, annual fee `[K]`), hardened runtime, `notarytool` + staple | GitHub Releases (notarized `.zip`/`.dmg`, SHA-256), own Homebrew tap (`brew install --cask <owner>/tap/<name>`) | Policy checklist §11; M2 exit |
| 2: 1.0 | General | Same | Plus the official `homebrew/cask` once notable. Official casks must pass Homebrew's Gatekeeper checks `[V~]` E16; unsigned casks were being removed by Sept 2026 `[S]` E16 | M3 exit |

Releases are cut from CI on a version tag. Creating the repository, tags, releases and pushes to public remotes are operator-approved acts. Signing secrets (certificate `.p12`, notary API key) live in GitHub Actions secrets; the procedure is documented and nothing is committed.

### 14.3 Updates

v1 has no auto-update (I9). Users update via Homebrew or GitHub. D-10 revisits an opt-in Sparkle 2 feed (EdDSA-signed appcast), which would need an explicit carve-out from I9.

### 14.4 Versioning

SemVer. CHANGELOG entries note any change to §10.2 (reach) or to the supported `claude-multiprofile` range (§8.1).

---

## 15. Upstream collaboration plan

### 15.1 Position `[D]` D-02 (ruled)

A separate public repository. `claude-multiprofile` is the foundation: everything Sidelauder knows about profiles comes from it (§7.0). Upstream stays a no-build-tools CLI; Sidelauder asks it for one read-only output.

| Option | Pros | Cons |
|---|---|---|
| **Separate repo on upstream's interface** (ruled) | Keeps upstream's trust surface and philosophy (E1, E6); independent release cadence and signing; no duplicated profile logic | Depends on upstream accepting U1, or on an interim adapter coupled to upstream internals |
| App inside the upstream repo (`apps/switcher/`) | One place for users | Adds Xcode, signing and notarization to a one-maintainer Node project; widens its SECURITY.md reach; unlikely to be accepted `[A]` |
| Fork of upstream | Full control | Splits the user base; loses upstream's doctor/launcher fixes |

### 15.2 Proposed upstream changes (issue first; each its own PR)

| PR | Change | Size | Why upstream benefits |
|---|---|---|---|
| U1 (critical path) | `claude-multiprofile status --json`: read-only, offline, versioned (schema v1, §8.1.1), with a stated bump policy and tests. Includes each profile's `displayName` and, optionally, `lastLaunch` from the launch log. The PR would also give the on-profile / stray classification one exported home (the helper and `doctor` each draw it inline), match processes at the start of the command line (4.1.26), and report `app.refreshing`: the four rules the interim adapter had to add (§8.1.3) | Small to medium; reuses existing exported functions (4.1.24) | Any integrator or script gets a stable view without parsing files or `ps`; `doctor`'s account check becomes reusable |
| U2 | Document the launcher contract: opening a profile's launcher launches or focuses it through the helper | Docs | Protects every integrator |
| U3 (later) | README "Companions" section linking Sidelauder | Docs | Discoverability |

v0.1's U2 (write the launch path into the registry) and U3 (`list --json`) are folded into U1.

Compatibility policy: Sidelauder supports `status --json` schema 1 and, through the interim adapter, the upstream versions it was tested against (0.1.31 onward). Anything else → the "upstream unavailable" state until updated. Appendix C has the draft issue text.

### 15.3 What Sidelauder will never ask upstream to do

Write anything for Sidelauder, add runtime dependencies, change launcher behaviour for Sidelauder's sake, or relax any of upstream's security properties. U1 adds an output, not a behaviour. If upstream declines U1, D-20 decides between keeping the pinned adapter and proposing another shape; re-implementing upstream's logic in Sidelauder is not an option (NG10).

---

## 16. Plan

### 16.1 M0: spikes (both modes de-risked together)

Each spike is a throwaway Swift command-line tool or app on the first user's Mac (macOS 27); the macOS 26 runs move to the M2 gate. Each ends with numbers, a pass/fail verdict and the design consequence. Accessibility grants, screen-recording reviews and sign-ins are the operator's hands, not the implementer's.

| ID | Question | Method | Pass | If it fails |
|---|---|---|---|---|
| S1 | Can Sidelauder activate a chosen instance (a) after a rail click, (b) from a hotkey while inactive? | 50 trials per ladder step (0–3) on macOS 27 | (a) ≥ 49/50 via step 1; (b) ≥ 49/50 via steps 0 + 1, or via step 2 within §12 targets | (b) fails → hotkeys show the rail with the item preselected (two-step), or D-03 revisits private APIs (opt-in) |
| S2 | `hide()`/`unhide()` from a non-active process on 26+ | 50 trials | ≥ 49/50 | Stack becomes the default policy; Solo only via rail click (Sidelauder active) |
| S3 | AX frame set on Claude windows: accuracy, minimum size, flicker; ordering variants 1 vs 2 | 30 switches per variant, screen recording reviewed frame by frame | ±1 pt; ≤ 1 visibly wrong frame | Accept residual flicker, or add a crossfade overlay (backlog) |
| S4 | Does Electron emit AX moved notifications during a live drag? | Log notification timestamps during drags | Stream ≥ 30 Hz | Hide the rail during drags (§9.5) |
| S5 | *Retired in v0.2*: matching argv to profiles is upstream's (§7.0) | — | — | — |
| S6 | Launch via launcher: time to first window, activation, helper dialog visibility, jump into slot | 20 cold launches + 5 with a stale clone | Window ≤ 5 s (fresh), ≤ 8 s (refresh); lands in slot | Longer timeouts; document the jump |
| S7 | Chromium AX side-effects from our observers | Claude CPU/RSS with vs without Sidelauder, 10 min × 3 instances | Within ±2 % CPU, ±3 % RSS | Reduce the observed notification set; observe only the active PID |
| S8 | *Retired in v0.2*: badges left v1 (NG5); the question stays in the backlog | — | — | — |
| S9 | Spaces, full screen, Stage Manager behaviour | Scripted scenarios | Documented behaviour matches §9.10 | Adjust the edge-case table; maybe force A under Stage Manager |
| S10 | Z-order: floating rail vs Claude menus, tooltips, sheets, Mission Control, screenshots | Manual | No overlap or occlusion bugs | Use `.normal` level + ordering relative to the Claude window number `[A]` |
| S11 | TCC grant stability across rebuilds with the Phase 0 signing identity | 10 rebuilds | Grant persists | Document the re-grant step for development |
| S12 | Can CI grant Accessibility to test binaries? | Try on a GitHub macOS runner | Grant works | AX tests stay local (default assumption) |
| S13 | Hotkey default collisions (macOS, Claude Desktop, common tools: Rectangle, Raycast, Alfred, input-source switching) | Inventory on the first user's Mac plus the tools' documented defaults | No collision with system or those tools' defaults | Change defaults |
| S14 | Do hidden instances keep working? | Start a long response and a Code-tab task, then hide the instance (and, separately, cover it fully) for 10 min; compare completion time and output with a visible run | Same completion within 10 % | Solo gains a "busy → don't hide" rule, or Stack becomes the default (D-06) |
| S15 | Which instance does a notification click activate when several copies run? | Trigger notifications from two hidden profiles; click each | The posting instance activates, 10/10 | Document it; the rail follows whatever activates; consider Stack for notification-heavy users |
| S16 | Interim adapter and upstream call | Adapter output vs `claude-multiprofile list` and `doctor` on a live registry (running, hidden, stray, stale copy, shared account); call cost cold and warm; login-shell discovery from a Dock-launched build | Agrees on every state; warm ≤ 200 ms; discovery finds both paths | Fix the adapter; widen the timeout; manual path entry |

#### 16.1.1 M0 results (2026-09-29, macOS 27.0, E32)

The operator's M0 prompt scoped this run to S16, then S1 to S3, S14 and S15. Reports: `docs/spikes/`.

| Spike | Verdict | Numbers | Consequence |
|---|---|---|---|
| S16 | **Pass** | Agrees with `list`, `doctor` and the live process table on every state shown; the rest through upstream's functions on fixtures. 124 ms per call (`--full` 281 ms). Discovery 20/20 from Dock-style launches, 95 ms | §8.1 rewritten around the adapter as built; §6.7 gains the interactive probe and the kill; bundling rejected (D-20) |
| S1 | **Pass**, on synthetic and real input | Every rung 50/50 from an app without Accessibility; click to front 39 / 55 ms, hotkey 38 / 45 ms (p50 / p95); step 2 349 / 434 ms. Real input: hotkeys 18/18 (42 / 51 ms), rail clicks 12/12 (31 / 35 ms) | §9.7 stands; D-03 ruled: forbid; launchers never opened with a modifier held (§9.6) |
| S2 | **Pass** | 50/50; hide 3 / 7 ms, unhide 2 / 6 ms; both calls return false while working | Solo is sound from Mode A; confirm by notification (§9.8) |
| S3 | **Accuracy pass**; flicker verdict at M1a | 100/100 within 1 pt; minimum window 600 × 400 pt; ordering 2 never showed the target outside the slot (0/50), ordering 1 did in 8 of 20 relocations; 2–4 in-between frames on a resize in both | Ordering 2 adopted (D-22); M1a exit gains the operator's flicker verdict |
| S13 | Partial | All defaults register; no enabled macOS shortcut collides | D-11 ruled; Claude's own shortcuts checked at M1a's start |
| S11 | Observed | Grant held across about a dozen rebuilds with a development certificate; an ad-hoc build's entry did not carry over | Phase 0 signs stably from the first build (§14.2) |
| S14 | **Pass for chat**; Code not measured | Chat answer: work ended at 14.1 s visible, 12.3 s hidden, 13.4 s fully covered, complete at the reveal (1.1 × T) in both; CPU 64 % visible, 10 % hidden, 63 % covered. Code: the session asked for approval before every call, so no unattended run was possible | D-06 decided: Solo. M1a's daily use checks hides over 5 minutes and Code; hidden approvals are a documented limit (4.2.23) |
| S15 | **Not run** | Harness ready and smoke-tested | Moved to M1a's daily use by the operator; nothing waits on it (the rail follows the activation) |

Not run in M0: S4, S6, S7, S9, S10, S12 and S15, and S14's Code part. The attached-rail parts of S4 and S10 were already M1b's; the rest move to the start of M1a. The sign-in trial (§9.11) needs every other Claude instance quit, including the one the implementer's session runs in, so it is the operator's, at M1a.

### 16.2 Milestones

| Milestone | Content | Exit criteria |
|---|---|---|
| M0 Spikes and foundation | Name (D-01, done); the public repository created with §11 P1–P3 in its first commit (done); the upstream issue opened (operator's act, Appendix C); the interim adapter (done); S16, S1–S3, S14 and S15 (§16.1.1) | Every M0 spike has a result or a recorded move to M1a (S15 and S14's Code part moved there); this spec revised (v0.3, adopted 2026-09-29); D-03, D-06 and D-11 settled |
| M1a Personal alpha | S6, S7, S9, S10 (floating rail), S12 and the rest of S13 first; shared core, Mode A, slot handoff with the floating rail (F-B1, F-B3, F-B6), keep visible, sign-in assistant, onboarding, diagnostics, Phase 0 signing | §12 targets met on macOS 27; guard suite and mutation runner green; 500-switch soak clean; the operator's flicker verdict on the real rail (S3); one week of daily use with no stuck-hidden or wrong-instance events, including a hide of over 5 minutes during a long answer, a Code session hidden while it works, and a notification click from a hidden profile (S14, S15) |
| M1b Attached rail | F-B2 (rail follows the window), F-B4 (make room); S4 and S10 for the attached rail | Rail-follow target (§12) met, or hide-during-drag in place; one more week of daily use |
| M2 First release (beta) | Developer ID + notarization; own tap; README; SECURITY.md; §11 re-checked; macOS 26 runs of S1–S3 and S9 | Clean install on a fresh macOS 26 and 27 machine; §11 all ✅ |
| M3 1.0 | Fixes from the beta; U1 merged, or D-20 decided | No open P1 bugs; compatibility matrix run |

### 16.3 Effort (assumptions, `[A]`)

Implementer time, in focused working days: M0 4–6, M1a 8–12, M1b 4–6, M2 4–6, M3 depends on feedback. Operator time: about 3 hours in M0 (Accessibility grants, the S3 flicker review, notification and sign-in trials), about an hour per later milestone, plus a week of daily use at M1a and at M1b. External waits: upstream's answer on U1 (one maintainer, no estimate) and Apple Developer Program enrolment before M2 (annual fee). Most uncertainty sits in S1, S3, S9 and S14. Re-estimate after M0.

**M0 (2026-09-29).** One implementer session built the adapter and its gates, the harnesses, and ran S16, S1, S2 and S3; a second ran the operator's trials. Operator time was about 45 minutes in the first session (two Accessibility grants, one reset, a screen recording, launcher dialogs) and about an hour in the second (S1's real input, S14's runs and retries). Hand-timed trials cost more than planned: three chat runs and three Code runs had to be discarded or stopped, and S15 moved to the built app. For M1a: prefer checks the operator makes once in daily use over timed trials, and time from the machine's own signals, not hand marks.

### 16.4 Backlog (explicitly not v1)

- Per-profile Dock badges through the Dock's accessibility tree (was F-X1; needs v0.1's S8 question answered first).
- Busy indicator from per-instance CPU (libproc) as a badge substitute.
- Crossfade overlay to hide switch flicker.
- Mode A "attached" placement via low-rate CGWindowList polling.
- Adapters for other profile tools (NG9).
- Launch a terminal with `claude-<name>` for the matching Code profile.
- Opt-in auto-update (D-10).
- Localization (strings already in a String Catalog).

---

## 17. Risks

| ID | Risk | Likelihood | Impact | Mitigation | Early signal |
|---|---|---|---|---|---|
| R1 | Activation from hotkeys is refused under cooperative activation | Low (S1: 100/100 on synthetic input, 18/18 hotkeys and 12/12 clicks on real input, macOS 27) | High (US3) | Ladder §9.7; S1; two-step fallback; D-03 | A refused switch in daily use, or on macOS 26 at M2 |
| R2 | Anthropic ships native multi-account in Claude Desktop | Medium | High (obsoletes the product) | Keep v1 lean; open-source; sunset gracefully | Changes in the linked feature requests (E1) |
| R3 | Upstream declines U1, or changes the internals the interim adapter imports | Medium | High (the foundation) | Issue first; adapter pinned per tested version; version gate; the "upstream unavailable" state; D-20 | Upstream's answer; its CHANGELOG |
| R4 | Claude Desktop changes its window structure (custom windows, several main windows) | Medium | Medium | Isolated AX adapter; the S3 check re-run per Claude release | Integration test failures on a new Claude |
| R5 | Users refuse the Accessibility grant | Medium | Medium | Mode A stands alone (G3); honest onboarding copy | Beta feedback |
| R6 | Supply-chain compromise of an AX-privileged binary | Low | High | T1 mitigations | — |
| R7 | Trademark or terms complaint | Low | Medium | §11 checklist; D-01 | — |
| R8 | Hotkey conflicts | Medium | Low | Configurable; S13 | Issues |
| R9 | Stage Manager / Spaces edge-case bugs | High | Low | Documented limits; Mode A fallback per switch | S9 |
| R10 | Single-maintainer bus factor | Medium | Medium | Small codebase, ADRs, this spec | — |
| R11 | Apple tightens AX, TCC or activation rules | Low | High | Public APIs only; Mode A as floor | macOS betas |
| R12 | Sign-in misrouting persists as a user pain | High | Medium | Sign-in assistant; duplicate-account warning | Duplicate-account events |
| R13 | Users expect lower memory use (N Electron instances) | Medium | Low | Document it: Sidelauder does not change Claude's footprint | Issues |
| R14 | Frame fighting with other window managers | Medium | Low | Feedback-loop guard; per-profile keep visible; docs | Issues |
| R15 | Name collision: NVIDIA's "Switchyard" LLM router (E30) | **Closed 2026-09-29**: renamed Sidelauder before the repository existed (D-01) | — | — | — |
| R16 | Notification clicks activate the wrong instance | Unknown (S15 not run in M0) | Medium | The rail follows; Stack option; checked in M1a's daily use | A notification click in daily use that brings forward another profile |
| R17 | Hidden instances are throttled, so Solo stalls long responses | Low for chat answers (S14: no slower hidden or covered); unknown for hides over 5 minutes and Code sessions | High (defeats Solo) | Busy rule if M1a's checks show a stall; keep visible per profile; hidden approvals documented (4.2.23) | A hidden answer or Code task found unfinished in daily use |
| R18 | A Dock-launched app cannot find `claude-multiprofile` or `node` | Low to medium (S16: 20/20 on the test Mac; fixtures show setups that need the interactive probe or a manual path) | Medium | Two probes (§6.7) with user confirmation; manual path | Beta reports of "upstream not found" |
| R19 | A hotkey launch stalls the launcher at its startup screen (4.1.27) | Certain without the rule | Medium (the profile does not open; a dialog appears) | Never open a launcher with a modifier held (§9.6); GD-7 partition | GD-7's "held" test |

---

## 18. Decisions

| ID | Decision | Options | Status |
|---|---|---|---|
| D-01 | Product name and whether to contact Anthropic pre-launch | Non-"Claude" name + referential tagline / ask Anthropic / both | **Name ruled 2026-09-29: Sidelauder** (the working name "Switchyard" is taken in the field, E30; the resemblance to "Claude" is an accepted risk under R7). Whether to ask Anthropic before M2 stays open (P7) |
| D-02 | Home | Separate repo / inside upstream / fork | **Ruled 2026-09-29:** separate repository, public from its first commit, on upstream's interface (§15) |
| D-03 | Private-API activation fallback | Forbid / opt-in setting | **Ruled 2026-09-29 (operator), on S1:** forbid in v1. Every public route worked 50/50 on synthetic input, and the operator's real-input check passed (18/18 hotkeys, 12/12 clicks) |
| D-04 | Minimum macOS | 14 / 15 / 26 | **Ruled 2026-09-29:** 26 |
| D-05 | First-run mode | Auto / A / B | Recommendation: Auto |
| D-06 | Default policy | Solo / Stack | **Decided 2026-09-29 on S14 (implementer; the operator may overrule): Solo** in both modes. A hidden or fully covered chat answer finished no later than a visible one, and hiding cut the instance's CPU about sixfold, while covering saved nothing. Revisited if M1a's daily use finds a hidden answer or Code task stalled (then Solo gains a busy rule); a hidden Code approval is a documented limit (4.2.23) |
| D-07 | Snap external activations into the slot (B) | On / Off | Recommendation: On, with per-profile keep visible |
| D-08 | Read `lastKnownAccountUuid` | On / Off | **Superseded 2026-09-29** by the foundation rule: Sidelauder reads no account data; upstream reports shared accounts (§8.5) |
| D-09 | Default avatar | Initials / app icon | Recommendation: Initials (trademark-safe) |
| D-10 | Updates | None / opt-in Sparkle | Recommendation: None in v1 |
| D-11 | Hotkey defaults | ⌃⌥digits / ⌘⌥digits / unset | **Ruled 2026-09-29 (operator):** ⌃⌥1…9, ⌃⌥] / ⌃⌥[, ⌃⌥Tab, ⌃⌥0 (§6.5). All register and none collides with an enabled macOS shortcut (S13, partial); launches from them wait for the modifiers' release (§9.6). Claude Desktop's own shortcuts are checked at M1a's start |
| D-12 | License | MIT / Apache-2.0 | Recommendation: MIT (matches upstream) |
| D-13 | Launch at login | Offered, off / on | Recommendation: Offered, off |
| D-14 | Default profile in rail | Yes / No | Recommendation: Yes |
| D-15 | Unhide hidden-by-us instances on quit | Yes / No | Recommendation: Yes |
| D-16 | Pre-open checks | Launcher path + bundle-ID prefix and Default signature / none | Recommendation: the checks, presented as sanity checks (§8.4) |
| D-17 | Build system | Thin xcodeproj + SwiftPM / XcodeGen / Tuist | Recommendation: Thin xcodeproj + SwiftPM |
| D-18 | Transiently disable `AXEnhancedUserInterface` when found on | Yes (restore) / never touch | Recommendation: Yes, restore immediately; never set true |
| D-19 | Beta distribution | Own tap + Releases / Releases only | Recommendation: Own tap + Releases |
| D-20 | If upstream declines U1 | Keep the pinned adapter / propose another shape (e.g., a documented Node module API) | Open until upstream answers. Re-implementing upstream is excluded (NG10), and so is **bundling a copy of upstream inside the app** (S16 §4: it would ship a JIT runtime of 60 to 170 MB under Sidelauder's signature and hardened-runtime exceptions, and classify by a second copy of upstream's rules while the launchers run the installed version's helper). **Ruled 2026-09-29 (operator):** no bundling; if discovery fails for a real share of beta users, ask upstream for a fixed install location (for example a Homebrew formula) before considering any bundled copy |
| D-21 | Build order | Both modes at once / staged | **Ruled 2026-09-29:** staged (M1a, M1b); both modes in the first public release |
| D-22 | Slot handoff ordering (§9.4) | 1: unhide, set frame / 2: set frame while hidden, unhide | **Decided 2026-09-29 on S3's frame counts:** 2 (0/50 switches showed the target outside the slot, against 8 of 20 relocations for 1). The operator's flicker verdict on the real rail is an M1a exit criterion |
| D-23 | Upstream calls | One call for everything / a cheap call plus `--full` | **Decided 2026-09-29 on S16:** split. The one call cost 227 ms median; the cheap call 124 ms, `--full` 281 ms at start and on a config change (§8.1.4) |

---

## 19. Evidence register

### 19.1 Sources (retrieved 2026-09-28; E23 re-read and E26–E32 on 2026-09-29)

| ID | Source | Tier | Used for |
|---|---|---|---|
| E1 | [`jmdarre-v/claude-multiprofile` README](https://github.com/jmdarre-v/claude-multiprofile) @ `a954e81` | V | 4.1.x, isolation, update model, sign-in, companions context |
| E2 | `src/desktop.js` @ `a954e81`: `buildLaunchAppleScript` (L114–193), `uniqueBundleId` (L300–312), `launchTargetFor` (L469–479), `desktopAccountUuid` (L240–250), `CLAUDE_APP_CANDIDATES` + `findClaudeApp` (L70–85) | V | Launch line, clone decision, bundle IDs, account UUID, app candidates |
| E3 | `src/appclone.js` @ `a954e81`: header, `CLONE_PARENT`, `clonePathFor` | V | Clone location, signing facts |
| E4 | `src/launchhelper.js` @ `a954e81`: header, `running`, `onProfile`, `refresh`, log format | V | Helper behaviour, PATH, identity matching |
| E5 | `src/registry.js`, `src/commands/add.js` (L270–290), `src/state.js` @ `a954e81` | V | Registry schema and location |
| E6 | `SECURITY.md` @ `a954e81` | V | Trust surface, one maintainer |
| E7 | `.github/workflows/test.yml` @ `a954e81` | V | Upstream CI |
| E8 | [Upstream issues](https://github.com/jmdarre-v/claude-multiprofile/issues?q=is%3Aissue) | V~ | No switcher request |
| E9 | `git log` of `jmdarre-v` and [`abnegate`](https://github.com/abnegate/claude-multiprofile) clones | V | Fork status, PR #8 |
| E10 | [odahcam/claude-desktop-profiles](https://github.com/odahcam/claude-desktop-profiles) | V~ | Prior art |
| E11 | [erorplex/claude-desktop-profiles-macos](https://github.com/erorplex/claude-desktop-profiles-macos) | V~ | Prior art |
| E12 | [WWDC23 "What's new in AppKit" notes](https://wwdcnotes.com/documentation/wwdc23-10054-whats-new-in-appkit/); [Apple `yieldActivation(to:)`](https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)?language=objc); [Apple `activate(from:options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)) | S (Apple doc pages not read in full); superseded by E26 for the header text | Cooperative activation |
| E13 | [Apple Developer Forums 793253](https://developer.apple.com/forums/thread/793253) | S | Silent failure when not frontmost |
| E14 | Search synthesis incl. [Apple Forums 739524](https://developer.apple.com/forums/thread/739524) | S | `activate(options:)` false from non-active |
| E15 | [Apple Forums 763878](https://developer.apple.com/forums/thread/763878); [FB15168205](https://github.com/feedback-assistant/reports/issues/552); [Eternal Storms](https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/) | S | Sequoia hotkey restriction |
| E16 | [Homebrew Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) (V~); [Homebrew discussion 6482](https://github.com/orgs/Homebrew/discussions/6482), [HN 45907259](https://news.ycombinator.com/item?id=45907259) (S) | V~/S | Gatekeeper requirement; Sept 2026 removal |
| E17 | [alt-tab-macos commit 8dd63c7](https://github.com/lwouis/alt-tab-macos/commit/8dd63c7) (via search synthesis) | S | Private focusing APIs |
| E18 | [Screen Recording permissions in Catalina](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/) (via search synthesis) | S | CGWindowList without permission |
| E19 | [Rectangle `AccessibilityElement.swift`](https://raw.githubusercontent.com/rxhanson/Rectangle/main/Rectangle/AccessibilityElement.swift) | V~ | Size→position→size; enhanced-UI disable |
| E20 | [Mozilla bug 1664992](https://bugzilla.mozilla.org/show_bug.cgi?id=1664992); [Electron PR 10305](https://github.com/electron/electron/pull/10305); [Electron accessibility docs](https://www.electronjs.org/docs/latest/tutorial/accessibility) | S | Chromium AX tree and enhanced-UI side-effects |
| E21 | [NotificationCounter](https://github.com/b4d/NotificationCounter); [SketchyBar discussion 317](https://github.com/FelixKratz/SketchyBar/discussions/317) | S | Dock badge via AX |
| E22 | [moomux issue 304](https://github.com/erickgnclvs/moomux/issues/304); [macos-app-template issue 61](https://github.com/tomada1114/macos-app-template/issues/61) | S | TCC and ad-hoc cdhash |
| E23 | [Claude Code — Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) (full page read 2026-09-28, re-read 2026-09-29; the §4.3 quotes are verbatim) | V | Credentials, login, trademark, ordinary usage |
| E24 | [Anthropic Consumer Terms](https://www.anthropic.com/legal/terms) | V~ | Sharing, automation, reverse engineering, interference |
| E25 | [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines) | V~ | No alterations, no implied endorsement |
| E26 | macOS 27 SDK AppKit headers (Xcode 27.0, 27A266a): `NSApplication.h` (`activate`, `yieldActivationToApplication:`), `NSRunningApplication.h` (`activateFromApplication:options:`, `hide`, `unhide`), `NSWorkspace.h` (`OpenConfiguration.activates`); a scan of every `macos(27` declaration | V | Cooperative activation; hide semantics; NG1 on 27 |
| E27 | `claude-multiprofile` 0.1.31 as installed from npm: `cli.js`, `commands/{list,status,rename,upgrade}.js`, `registry.js`, `detect.js`, `appclone.js` (`clonePathFor`, `runningCopies`, `cloneIsRunning`), `desktop.js` (`launchTargetFor`, `dataDirInUse`, `desktopAccountUuid`, `buildLaunchAppleScript`), `launchhelper.js` (`running`, `onProfile`, log path), `updates.js` | V | Foundation table, exports, rename, no network |
| E28 | Measurements on the first user's Mac, 2026-09-29: macOS 27.0, arm64; Xcode 27.0, Swift 6.4; Claude 2.9939.4 (`LSMinimumSystemVersion` 13.0); registry names vs launcher filenames; `config.json` key names (values not read); `claude-multiprofile list` 1.47 s cold, 0.09 s warm; one module import 0.06 s | V | 3.1, 4.1.19–4.1.25, 7.4 |
| E29 | [anthropics/claude-code#18435](https://github.com/anthropics/claude-code/issues/18435) (feature request: several accounts in Claude Desktop), with search synthesis | S | R2: no native multi-account switching yet |
| E30 | [NVIDIA-NeMo/Switchyard](https://github.com/NVIDIA-NeMo/Switchyard), 3.2k stars, active 2026-09-29: "lets LLM applications route traffic across models and providers" | V | D-01, R15 |
| E31 | `claude-multiprofile` 0.1.31 as installed, read again for M0: `commands/doctor.js` (`checkOwnVersion` runs `npm view`; `checkDesktopLaunchPath`'s inline stray test), `appclone.js` (`parseRunningCopies` matches by substring), `launchhelper.js` (`running`, `onProfile`, `refresh` and its `.refreshing` copy), `state.js` (`toolVersion`) | V | 4.1.22, 4.1.24, 4.1.26, §8.1.3 |
| E32 | M0 spike reports, `docs/spikes/` (S1 with its real-input check, S2, S3, S14, S16, S15's move, and the S11 and S13 observations in the index), measured 2026-09-29 on macOS 27.0, Apple silicon, with the harnesses in `spikes/` | V | 4.1.10, 4.1.20, 4.1.27, 4.2.4, 4.2.11, 4.2.17, 4.2.19–4.2.23, §6.7, §8.1, §9.4, §9.6–§9.10, §16.1.1 |

### 19.2 Assumptions

| ID | Assumption | Spike |
|---|---|---|
| A1 | Claude's main window is a standard `AXWindow` with settable position and size | S3: **holds** (100/100 within 1 pt) |
| A2 | Electron honours AX frame sets without fighting back (beyond its minimum size) | S3: **holds**; the minimum is 600 × 400 pt |
| A3 | `hide()`/`unhide()` work from a non-active process on 26+ | S2: **holds on 27** (50/50); 26 at M2 |
| A4 | *Retired in v0.2*: argv reading moved upstream | — |
| A5 | Opening a running profile's launcher brings that instance forward from a non-active caller | S1: **holds** (50/50, 349 ms), with no modifier held; the previous window shows again for ~150 ms |
| A6 | Window-level AX observation does not switch on Chromium's full accessibility tree | S7 |
| A7 | *Retired in v0.2* with the badges (NG5) | — |
| A8 | Setting `kAXFrontmostAttribute` is an effective activation fallback | S1: **holds** (100/100), except on an instance just hidden and unhidden (1/50, 4.2.21) |
| A9 | A `.floating` rail does not conflict with Claude's own menus, sheets and tooltips | S10 |
| A10 | *Resolved in v0.2*: the first user runs macOS 27 on Apple silicon (E28) | — |
| A11 | Upstream is receptive to U1 (evidence: it merged PR #8 from a fork owner) | Issue |
| A12 | The upstream functions the interim adapter imports stay stable until U1 lands | S16: pinned to 0.1.31 and gated (§8.1.3); re-tested per upstream release |
| A13 | GitHub macOS runners can run GUI fixture apps but cannot grant Accessibility | S12 |
| A14 | A stable non-ad-hoc signing identity keeps the TCC grant across rebuilds | S11, observed: **holds** with a development certificate, when used from the first build |
| A15 | Stage Manager state is readable from `com.apple.WindowManager` → `GloballyEnabled` | S9 |
| A16 | Claude reopens a window when activated with none open | S6 |
| A17 | A hotkey lets Sidelauder activate itself under cooperative activation | S1: **holds** (100/100 synthetic, p95 15 ms; 18/18 real) |
| A18 | Hidden or fully covered instances keep working at full speed | S14: **holds for a chat answer** (no slower hidden or covered); hides over 5 minutes and Code sessions at M1a |
| A19 | A notification click activates the instance that posted it | S15: not run; M1a's daily use |
| A20 | A Dock-launched app can find `claude-multiprofile` and `node` through the user's login shell | S16: **holds** on the test Mac (20/20); fixtures show the setups that need the interactive probe or a manual path |

---

## 20. Glossary

| Term | Plain meaning |
|---|---|
| Accessibility (AX) API | The macOS interface assistive tools and window managers use to read and move other apps' windows; needs a user grant |
| TCC | macOS's privacy-permission system (Transparency, Consent and Control) that records grants like Accessibility |
| Cooperative activation | The macOS 14+ rule that bringing an app to the front is a request the current front app must yield to |
| Bundle ID | An app's reverse-DNS identity (e.g., `com.anthropic.claudefordesktop`) |
| APFS clone | An instant copy-on-write duplicate of a file or folder that shares disk blocks with the original |
| `--user-data-dir` | The Electron/Chromium flag that points an instance at its own data folder |
| Launcher / launch helper | Upstream's per-profile AppleScript app and the JXA script it runs to refresh the copy and open Claude |
| Stray instance | A profile's Claude copy running without its data-folder flag, and therefore on the default account |
| Slot | Mode B's shared window frame that every profile's window, except kept-visible ones, occupies when active |
| Kept-visible profile | A profile never hidden by Solo and never moved into the slot |
| Upstream interface | `claude-multiprofile`'s read-only status output, Sidelauder's only source of profile knowledge |
| Liveness check | The act-time test that a process is still the one upstream reported: same PID, bundle and start time |
| Solo / Stack | Hide the other profiles after a switch / leave them where they are |
| Space | A macOS virtual desktop |
| Stage Manager | A macOS window-grouping mode that re-arranges windows on its own |
| Hardened runtime | A macOS code-signing mode that blocks code injection and requires notarization-compatible settings |
| Notarization | Apple's automated malware scan for apps distributed outside the App Store; required for smooth Gatekeeper acceptance |
| Developer ID | The Apple certificate used to sign apps distributed outside the App Store |
| Team ID | The identifier of the Apple developer account that signed an app |
| cdhash | A hash of an app's signed code; ad-hoc builds are identified by it, so every rebuild looks like a new app |
| `AXEnhancedUserInterface` | An attribute screen readers set; in Chromium/Electron it turns on the full accessibility tree and can slow window moves |
| CGWindowList | The CoreGraphics call that lists on-screen windows with their bounds and owner process |
| Registry | Upstream's `profiles.json` listing every profile |
| Guard / red mutation | A check protecting an invariant / a deliberate code change that disables the check and must make a test fail |

---

## Appendix A: Pseudocode

### A.1 Liveness (GD-1)

```swift
struct Observed { let pid: pid_t; let bundleURL: URL; let startTime: timeval }

/// On each upstream answer: keep only PIDs that are what upstream says they are.
func observe(_ reported: ReportedInstance, fs: CaseAwareCompare) -> Observed? {
    guard let app = NSRunningApplication(processIdentifier: reported.pid),
          app.bundleIdentifier == claudeBundleID, app.activationPolicy == .regular,
          let url = app.bundleURL, fs.same(url, reported.appPath),
          let start = processStartTime(reported.pid)            // sysctl KERN_PROC_PID; never argv
    else { return nil }                                         // → discard and re-query once
    return Observed(pid: reported.pid, bundleURL: url, startTime: start)
}

/// At the moment of acting.
func holds(_ o: Observed, fs: CaseAwareCompare) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: o.pid), !app.isTerminated,
          let url = app.bundleURL, fs.same(url, o.bundleURL),
          let start = processStartTime(o.pid) else { return false }
    return start == o.startTime
}
```

### A.2 Coordinate conversion

```swift
/// AX/CG global (top-left origin, y down) → AppKit global (bottom-left origin, y up).
func toAppKit(_ r: CGRect, primaryMaxY: CGFloat) -> CGRect {
    CGRect(x: r.minX, y: primaryMaxY - (r.minY + r.height), width: r.width, height: r.height)
}
```

### A.3 Set frame (after Rectangle, E19)

```swift
func setFrame(_ w: AXWindow, _ target: CGRect) throws {
    try w.setSize(target.size)        // may be clamped to the current display
    try w.setPosition(target.origin)
    try w.setSize(target.size)        // re-apply once on the destination display
    suppressNotifications(for: w, milliseconds: 150)   // feedback-loop guard (§9.9)
}
```

### A.4 Enhanced-UI wrapper (GD-5)

```swift
func withEnhancedUIDisabledIfOn<T>(_ app: AXApp, _ body: () throws -> T) rethrows -> T {
    let prior = app.enhancedUserInterface          // Bool? (nil = unsupported)
    if prior == true { app.enhancedUserInterface = false }
    defer { if prior == true { app.enhancedUserInterface = true } }   // restore only; never set true otherwise
    return try body()
}
```

---

## Appendix B: `rail.json` JSON Schema (v1)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Sidelauder rail state",
  "type": "object",
  "required": ["version"],
  "additionalProperties": false,
  "properties": {
    "version": { "const": 1 },
    "order": { "type": "array", "items": { "type": "string", "minLength": 1 }, "uniqueItems": true },
    "profiles": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "nickname": { "type": "string", "maxLength": 40 },
          "avatar": {
            "type": "object",
            "required": ["kind"],
            "additionalProperties": false,
            "properties": {
              "kind": { "enum": ["initials", "appIcon"] },
              "text": { "type": "string", "maxLength": 2 },
              "color": { "type": "string", "pattern": "^#[0-9A-Fa-f]{6}$" }
            }
          },
          "keepVisible": { "type": "boolean" },
          "hiddenFromRail": { "type": "boolean" }
        }
      }
    },
    "slots": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["x", "y", "w", "h"],
        "additionalProperties": false,
        "properties": {
          "x": { "type": "number" }, "y": { "type": "number" },
          "w": { "type": "number", "exclusiveMinimum": 0 }, "h": { "type": "number", "exclusiveMinimum": 0 },
          "screen": { "type": "string" }
        }
      }
    }
  }
}
```

Keys of `profiles` are upstream profile names, plus `default`.

---

## Appendix C: Draft upstream issue (for `jmdarre-v/claude-multiprofile`; the operator posts it)

> **Title:** Read-only `status --json` for companion tools?
>
> Would you accept a read-only, offline `claude-multiprofile status --json`? Thank you for this tool; I'd like to build on it rather than beside it.
>
> I'm writing a small open-source macOS companion: a Slack-style rail that switches between the Desktop profiles this tool creates. It brings one profile's window forward and hides the others. It never writes this tool's files or touches Claude's bundle, data, Keychain or updater. It launches profiles only by opening their launcher `.app`, so the helper's refresh and wrong-account checks still apply.
>
> To stay on top of your tool, it needs what the tool already knows, as data:
> - per profile: name, display name, colour, launcher path and bundle ID, app-copy path (dedicated, stale, refreshing), data folder;
> - the default install;
> - running instances per profile, with the tool's own classification (on-profile, running without its data folder, and so on);
> - which profiles share an account, as profile names only, never the account ID;
> - a `schemaVersion`, bumped on breaking changes.
>
> Everything in it comes from functions the tool already exports. I'm happy to write the PR with tests in the repository's style, in whatever shape you prefer. Until then, my app calls the installed package's exported functions, pinned to the versions I've tested, and I'll delete that the day a `--json` output exists. The app stays outside this repo, since it needs Xcode, signing and Accessibility.

---

## Appendix D: Challenge outcomes (v0.1 → v0.2, 2026-09-29)

**Rulings.** Build staged (D-21). `claude-multiprofile` is the foundation: "Under the hood, foundations-wise, I want to completely build upon `claude-multiprofile` as a solution, not duplicate or reinvent anything from there" (§7.0; D-08 superseded). The repository is public from its first commit (D-02). The platform floor is macOS 26 (D-04).

| # | v0.1 question | Outcome | Evidence and change |
|---|---|---|---|
| 1 | Is "no embedding" absolute? | Stands | No hosting API among the macOS 27 SDK's AppKit additions (4.2.18, E26) |
| 2 | Does the activation ladder work? | Changes | Header text now primary (E26). Step 0 added for hotkeys; step 2 opens the launcher, not the app copy; direct launches removed (§9.7, §5.4). Still spike-bound (S1) |
| 3 | Is Mode B non-interfering? | Stands, with two new unknowns | Frame writes land in Claude's own window state exactly as a user drag does. New unknowns: hidden-instance throttling (S14) and notification routing (S15) |
| 4 | Solo vs side by side; is undock enough? | Changes | Solo defined once: hide every other visible instance, and only after confirmed activation (v0.1 defined it two ways and hid without confirmation). Undock became keep visible, in both modes (F-C13) |
| 5 | Is the separate repo right? | Changes | Separate and public from the first commit; upstream becomes the foundation and U1 (`status --json`) the critical path (§7.0, §15) |
| 6 | Policy interpretations | Stands, reworded | Quotes verified verbatim (E23) and applied to Desktop by analogy. v0.1's "reads no token files" was false: its one permitted file, `config.json`, holds the encrypted sign-in cache (4.1.25). Now Sidelauder's code opens nothing in a data folder (I3) |
| 7 | Is identity resolution complete? | Moved upstream | Sidelauder checks liveness only (§8.4). v0.1's rename migration could never match: `rename` moves every key it matched on (4.1.21) |
| 8 | Are the §12 targets realistic? | Stands, pending S1 and S3 | Upstream calls kept off the switch path (4.1.20) |
| 9 | Is Mode A worth shipping on its own? | Changes | Yes, once it stops covering Claude's content: v0.1's edge rail sat over the sidebar of any window flush with the edge; now a free edge or an edge tab (§6.3) |
| 10 | Is §10.2 broader than needed? | Changes | Dock access, argv reading and account reading removed |
| 11 | Are the estimates credible? | Changes | No: 13 spikes on three macOS versions in 3–5 days was not credible, and operator time was missing. Now macOS 27 in M0, 26 at M2, operator time counted (§16.3) |
| 12 | Anything missing? | Changes | Hidden-instance throttling (S14), notification routing (S15), finding upstream from a Dock-launched app (S16), the name collision (R15, E30), the first user's macOS 27 (A10), display names (4.1.19) |

## Appendix E: M0 outcomes (v0.2 → v0.3, 2026-09-29)

**Ruled before M0.** The name is Sidelauder (D-01); the repository's reviews run through loupe, with `review.toml` and `AGENTS.md` in the tree.

| # | Question | Outcome | Evidence and change |
|---|---|---|---|
| 1 | Does the interim adapter agree with upstream? | Stands, with its composition made explicit | S16: agrees on every state shown. Four rules upstream draws inline are named in the adapter (§8.1.3, E1–E4); each instance now carries its `appPath`; `unmanagedInstances` is dropped; untested versions exit 3 |
| 2 | What does an upstream call cost? | Changes | One call cost 227 ms; the split (D-23) gives 124 ms on process events and 281 ms with `--full` at start and on a config change |
| 3 | Can a Dock-launched app find upstream? | Stands, with a second probe | 20/20 on the test Mac. A terminal launch inherits the shell's environment (4.1.10), so the test had to imitate the Dock; an interactive zsh ignores SIGTERM, so a probe is killed as a group (§6.7) |
| 4 | Would bundling upstream be better than calling the installed one? | No | S16 §4: a JIT runtime under Sidelauder's signature, a second copy of upstream's rules, two security-update streams. The fallback beside D-20 is a fixed install location from upstream |
| 5 | Does the activation ladder work? | Stands | S1: every rung 50/50 without Accessibility, click to front 39 ms; on real input 18/18 hotkeys and 12/12 clicks. Nothing was refused (R1). Step 2 shows the previous window again; step 3 fails after a hide and unhide (4.2.21) |
| 6 | Can a hotkey launch a profile? | Changes | A launcher opened with Control held stops at its startup screen (4.1.27); launches wait for the modifiers' release (§9.6, R19, GD-7) |
| 7 | Do hide and unhide work from Mode A? | Stands | S2: 50/50, under 7 ms; the calls' return values are not evidence (4.2.20) |
| 8 | Does the slot handoff land, and which ordering? | Stands; ordering 2 | S3: 100/100 within 1 pt; ordering 2 never showed the target outside the slot (D-22); minimum window 600 × 400 pt. Flicker is the operator's verdict at M1a |
| 9 | Were v0.2's upstream facts right? | One correction | `doctor` makes a network call (4.1.22); `runningCopies` matches by substring (4.1.26); no exported classification or refresh state (4.1.24) |
| 10 | Does the Accessibility grant survive rebuilds? | Observed | With a development certificate from the first build, yes; an ad-hoc build's entry does not carry over (4.2.11, §14.2) |
| 11 | Do hidden or covered instances keep working? | Stands for chat; Solo decided | S14: a chat answer finished no later hidden or covered; hiding cut CPU about sixfold, covering saved nothing (4.2.17, D-06). The Code tab asked for approval before every call, so Code went unmeasured and hidden approvals became a documented limit (4.2.23) |
| 12 | What is left of M0? | Moved to M1a | S15, S14's Code part and hides over 5 minutes, all in M1a's daily use (§16.2); S4, S6, S7, S9, S10, S12 and the rest of S13 at M1a's start |

*End of specification v0.3.*
