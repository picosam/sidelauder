// S14 (do hidden or covered instances keep working?) and S15 (which instance
// does a notification click activate?). Both need the operator's hands: they
// type into Claude and click notifications; this runner never does (I6).
//
// The operator marks moments with hotkeys that only SpikeRunner receives:
//   ⌃⌥⇧1  start (S14: prompt sent in A; S15: prompt sent in A, hide A)
//   ⌃⌥⇧2  S14: finished;  S15: prompt sent in B, hide B
//   ⌃⌥⇧3  S14: at the reveal it was still streaming
//   ⌃⌥⇧4  S15: I clicked A's notification
//   ⌃⌥⇧5  S15: I clicked B's notification
//   ⌃⌥⇧9  stop

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
final class HiddenSpikes {
    let log: ResultLog
    let watch: WorkspaceWatch
    let act: ActivationSpikes
    let insts: [Instance]
    var marks: [(id: UInt32, t: Double)] = []

    init(log: ResultLog, watch: WorkspaceWatch, act: ActivationSpikes, insts: [Instance]) {
        self.log = log; self.watch = watch; self.act = act; self.insts = insts
    }

    func registerMarks() -> [String: Int] {
        var st: [String: Int] = [:]
        for n in [1, 2, 3, 4, 5, 9] {
            st["ctrl-opt-shift-\(n)"] = Int(HotKeys.register(id: UInt32(n), keyCode: digitKeys[n], modifiers: ctrlOptShift))
        }
        hotKeyHandler = { [weak self] id in
            let t = nowMs()
            MainActor.assumeIsolated {
                self?.marks.append((id, t))
                self?.log.write(["mark": Int(id)])
                NSSound.beep()
            }
        }
        return st
    }

    func nextMark(after t: Double, among ids: Set<UInt32>, timeoutMs: Double) async -> (id: UInt32, t: Double)? {
        var hit: (id: UInt32, t: Double)?
        _ = await waitUntil(timeoutMs: timeoutMs, stepMs: 20) {
            hit = self.marks.first { $0.t > t && ids.contains($0.id) }
            return hit != nil
        }
        return hit
    }

    func treeCpuMs(_ pid: pid_t) -> Double { processTree(pid).compactMap(cpuMs).reduce(0, +) }

    /// From the window list: is every on-screen window of `a` inside one
    /// window of `b` that is in front of it? Chromium counts a window as
    /// occluded only when nothing of it shows.
    func fullyCovered(_ a: pid_t, by b: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        func rect(_ w: [String: Any]) -> CGRect {
            let d = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return CGRect(x: d["X"] ?? 0, y: d["Y"] ?? 0, width: d["Width"] ?? 0, height: d["Height"] ?? 0)
        }
        let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 && rect($0).width > 50 }
        let aWins = normal.enumerated().filter { ($0.element[kCGWindowOwnerPID as String] as? pid_t) == a }
        guard !aWins.isEmpty else { return false }
        return aWins.allSatisfy { ai in
            normal.prefix(ai.offset).contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == b && rect($0).contains(rect(ai.element)) }
        }
    }

    // MARK: S14

    func s14(condition: String, kind: String, revealAfter: Double?, maxSeconds: Double) async {
        let a = insts[0]
        guard let appA = a.app else { log.write(["spike": "S14", "error": "instance gone"]); return }
        let hk = registerMarks()
        log.write(["spike": "S14", "event": "ready", "condition": condition, "kind": kind,
                   "revealAfterS": revealAfter.map { $0 as Any } ?? NSNull(), "hotkeys": hk, "axTrusted": axTrusted()])

        // Baseline CPU for 5 s before the start mark.
        var last = treeCpuMs(a.pid), lastT = nowMs()
        var baseline: [Double] = []
        var start: (id: UInt32, t: Double)?
        while start == nil {
            start = await nextMark(after: 0, among: [1, 9], timeoutMs: 1000)
            let c = treeCpuMs(a.pid), t = nowMs()
            baseline.append((c - last) / (t - lastT) * 100)
            if baseline.count > 5 { baseline.removeFirst() }
            last = c; lastT = t
        }
        guard let s = start, s.id == 1 else { log.write(["spike": "S14", "event": "stopped"]); return }
        let t0 = s.t

        // Apply the condition.
        var coverRestore: (AXUIElement, CGRect)?
        var applied: [String: Any] = [:]
        switch condition {
        case "hidden":
            appA.hide()
            applied["hidden"] = await waitUntil(timeoutMs: 1000) { appA.isHidden } != nil
        case "covered":
            if insts.count > 1, let appB = insts[1].app, let wa = axMainWindow(a.pid), let fa = axFrame(wa),
               let wb = axMainWindow(insts[1].pid), let fb = axFrame(wb) {
                applied["setFrame"] = axSetFrame(wb, fa.insetBy(dx: -8, dy: -8))
                coverRestore = (wb, fb)
                _ = act.step1(appB)
                _ = await waitUntil(timeoutMs: 500) { frontmostPid() == appB.processIdentifier }
                if frontmostPid() != appB.processIdentifier { _ = act.step3(appB.processIdentifier) }
                applied["fullyCovered"] = await waitUntil(timeoutMs: 1000) { self.fullyCovered(a.pid, by: appB.processIdentifier) } != nil
            } else {
                applied["error"] = "no windows to cover with"
            }
        default: break
        }
        log.write(["spike": "S14", "event": "start", "condition": condition, "applied": applied,
                   "baselineCpuPct": baseline.map { round1($0) }])

        var revealed: Double?
        var samples: [Double] = []
        last = treeCpuMs(a.pid); lastT = nowMs()
        var finished: (id: UInt32, t: Double)?
        while finished == nil && nowMs() - t0 < maxSeconds * 1000 {
            finished = await nextMark(after: t0, among: [2, 9], timeoutMs: 1000)
            let c = treeCpuMs(a.pid), t = nowMs()
            let pct = (c - last) / (t - lastT) * 100
            samples.append(pct)
            log.write(["spike": "S14", "sample": round1((t - t0) / 1000), "cpuPct": round1(pct), "hidden": appA.isHidden])
            last = c; lastT = t
            if revealed == nil, let r = revealAfter, condition != "visible", t - t0 >= r * 1000 {
                if let (w, f) = coverRestore { _ = axSetFrame(w, f) }
                appA.unhide()
                // Step 1, not AX alone: AX frontmost fails right after a hide
                // and unhide (4.2.21).
                _ = await waitUntil(timeoutMs: 500) { !appA.isHidden }
                _ = act.step1(appA)
                if await waitUntil(timeoutMs: 300, { frontmostPid() == a.pid }) == nil { _ = act.step3(a.pid) }
                revealed = t
                log.write(["spike": "S14", "event": "revealed", "atS": round1((t - t0) / 1000),
                           "aFront": frontmostPid() == a.pid, "aHidden": appA.isHidden])
            }
        }
        let streaming = marks.first { $0.t > t0 && $0.id == 3 }
        log.write(["spike": "S14", "event": "end", "condition": condition, "kind": kind,
                   "finishedS": round1(finished.map { ($0.t - t0) / 1000 }), "stoppedEarly": finished?.id == 9,
                   "revealedS": round1(revealed.map { ($0 - t0) / 1000 }),
                   "stillStreamingAtReveal": streaming != nil,
                   "cpuPctMedian": round1(percentile(samples, 0.5)), "cpuPctP95": round1(percentile(samples, 0.95))])
        if appA.isHidden { appA.unhide() }
        if let (w, f) = coverRestore { _ = axSetFrame(w, f) }
        HotKeys.unregisterAll()
    }

    // MARK: S15

    /// A, B, self, another Claude copy, or "other"; never a name.
    func label(_ pid: pid_t) -> String {
        if let i = insts.first(where: { $0.pid == pid }) { return i.label }
        if pid == getpid() { return "self" }
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        return bid == "com.anthropic.claudefordesktop" ? "other-claude" : "other"
    }

    func s15(clicks: Int) async {
        let hk = registerMarks()
        log.write(["spike": "S15", "event": "ready", "hotkeys": hk])
        var lastDecl = nowMs()
        var done = 0
        while done < clicks {
            guard let m = await nextMark(after: lastDecl, among: [1, 2, 4, 5, 9], timeoutMs: 30 * 60 * 1000) else { break }
            lastDecl = m.t
            switch m.id {
            case 1, 2:
                let i = insts[Int(m.id) - 1]
                i.app?.hide()
                log.write(["spike": "S15", "event": "hid", "instance": i.label])
            case 4, 5:
                // The click came before the declaration; attribute the last
                // Claude activation since the previous declaration.
                // The window is from the previous mark of any kind.
                let clicked = m.id == 4 ? "A" : "B"
                let acts = watch.all(after: marks.last { $0.t < m.t }?.t ?? 0)
                    .filter { $0.kind == "activate" && $0.t <= m.t && $0.pid != getpid() }
                let activated = acts.last.map { label($0.pid) } ?? "none"
                done += 1
                log.write(["spike": "S15", "click": done, "clicked": clicked, "activated": activated,
                           "ok": activated == clicked,
                           "activationsSeen": acts.map { label($0.pid) }])
            default:
                done = clicks
            }
        }
        log.write(["spike": "S15", "event": "end"])
        HotKeys.unregisterAll()
        for i in insts where i.app?.isHidden == true { i.app?.unhide() }
    }
}
