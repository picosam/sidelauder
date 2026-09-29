// S3: the Mode B slot handoff (spec §9.4). Accuracy of AX frame sets on
// Claude windows, the minimum size, and ordering variant 1 (unhide, set
// frame, activate, hide source) against variant 2 (set the frame while the
// target is hidden, then unhide and activate, hide source).
//
// Flicker is judged from a screen recording the operator makes and reviews;
// this runner flashes a sync marker at start and end and logs every step's
// time from it, so each switch can be found in the recording.
//
// Window-level AX only (spec I6): position, size, frontmost, raise. The
// original frames and hidden states are restored at the end.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class FrameSpikes {
    let log: ResultLog
    let watch: WorkspaceWatch
    let panel: RailPanel
    let act: ActivationSpikes
    let insts: [Instance]

    init(log: ResultLog, watch: WorkspaceWatch, panel: RailPanel, act: ActivationSpikes, insts: [Instance]) {
        self.log = log; self.watch = watch; self.panel = panel; self.act = act; self.insts = insts
    }

    func flash(_ color: NSColor) async {
        let s = NSScreen.screens[0].frame
        let w = NSPanel(contentRect: NSRect(x: s.midX - 120, y: s.midY - 120, width: 240, height: 240),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.backgroundColor = color
        w.orderFrontRegardless()
        await sleepMs(400)
        w.orderOut(nil)
    }

    func waitWindow(_ pid: pid_t, timeoutMs: Double) async -> AXUIElement? {
        var found: AXUIElement?
        _ = await waitUntil(timeoutMs: timeoutMs, stepMs: 10) { found = axMainWindow(pid); return found != nil }
        return found
    }

    func s3(variant: Int, switches: Int) async {
        guard axTrusted() else { log.write(["spike": "S3", "error": "no Accessibility grant"]); return }
        let a = insts[0], b = insts[1]
        guard let appA = a.app, let appB = b.app else { log.write(["spike": "S3", "error": "instance gone"]); return }

        // Originals, restored at the end.
        let origFrames = [a.pid: axMainWindow(a.pid).flatMap(axFrame), b.pid: axMainWindow(b.pid).flatMap(axFrame)]
        let origHidden = [a.pid: appA.isHidden, b.pid: appB.isHidden]
        let enhanced = insts.prefix(2).map { axCopy(axApp($0.pid), "AXEnhancedUserInterface") as? Bool }

        // The starting state Solo leaves: A in front, B hidden.
        if appA.isHidden { appA.unhide() }
        _ = await act.makeFront(a)
        appB.hide()
        _ = await waitUntil(timeoutMs: 1000) { appB.isHidden }
        guard let slot = axMainWindow(a.pid).flatMap(axFrame) else { log.write(["spike": "S3", "error": "no window for A"]); return }
        panel.orderFrontRegardless()

        let origin = nowMs()
        log.write(["spike": "S3", "event": "start", "variant": variant, "switches": switches, "slot": slot.dict,
                   "enhancedUI": enhanced.map { $0.map { $0 as Any } ?? NSNull() }, "syncAt": 0])
        await flash(.systemPink)

        for k in 1...switches {
            let src = k % 2 == 1 ? a : b, dst = k % 2 == 1 ? b : a
            guard let srcApp = src.app, let dstApp = dst.app else { break }
            var steps: [String: Any] = [:]
            func mark(_ name: String) { steps[name] = round1(nowMs() - origin) }

            // The rail click: SpikeRunner becomes active, as it would on a click.
            var clicked = false
            panel.view.onMouseDown = { _ in clicked = true }
            mark("click")
            guard Poster.click(panel) else { log.write(["spike": "S3", "switch": k, "error": "panel not topmost"]); break }
            _ = await waitUntil(timeoutMs: 300) { clicked && NSApp.isActive }

            var errors: [String] = []
            var windowWhileHidden: Bool?
            var w: AXUIElement?
            if variant == 2 {
                w = axMainWindow(dst.pid)
                windowWhileHidden = w != nil
                if let w { mark("frameSet"); errors = axSetFrame(w, slot) }
                mark("unhide"); dstApp.unhide()
                _ = await waitUntil(timeoutMs: 500) { !dstApp.isHidden }
                if w == nil { w = await waitWindow(dst.pid, timeoutMs: 800); if let w { mark("frameSet"); errors = axSetFrame(w, slot) } }
            } else {
                mark("unhide"); dstApp.unhide()
                _ = await waitUntil(timeoutMs: 500) { !dstApp.isHidden }
                w = await waitWindow(dst.pid, timeoutMs: 800)
                if let w { mark("frameSet"); errors = axSetFrame(w, slot) }
            }
            mark("activate")
            let allowed = act.step1(dstApp)
            let t0 = nowMs()
            let activated = await waitUntil(timeoutMs: 400) { self.watch.first("activate", pid: dst.pid, after: t0) != nil }
            if activated != nil { mark("hideSource"); srcApp.hide() }
            _ = await waitUntil(timeoutMs: 500) { srcApp.isHidden }
            mark("done")
            let actual = w.flatMap(axFrame)
            log.write(["spike": "S3", "variant": variant, "switch": k, "from": src.label, "to": dst.label,
                       "steps": steps, "axErrors": errors, "allowed": allowed,
                       "windowFoundWhileHidden": windowWhileHidden.map { $0 as Any } ?? NSNull(),
                       "actual": actual?.dict ?? [:], "within1pt": actual?.within(slot, 1) ?? false,
                       "activated": activated != nil, "sourceHidden": srcApp.isHidden,
                       "switchMs": round1(nowMs() - origin - ((steps["click"] as? Double) ?? 0))])
            panel.view.onMouseDown = nil
            await sleepMs(1500)
        }
        await flash(.systemPink)
        log.write(["spike": "S3", "event": "end", "syncAt": round1(nowMs() - origin)])

        // The minimum size: ask for a small frame once, read what Claude allows.
        if let front = [a, b].first(where: { $0.app?.isHidden == false }), let w = axMainWindow(front.pid) {
            let small = CGRect(x: slot.minX, y: slot.minY, width: 320, height: 240)
            let errs = axSetFrame(w, small)
            log.write(["spike": "S3", "event": "minimumSize", "asked": small.dict, "actual": axFrame(w)?.dict ?? [:], "axErrors": errs])
            _ = axSetFrame(w, slot)
        }

        // Restore.
        for i in [a, b] {
            if let f = origFrames[i.pid] ?? nil, let w = axMainWindow(i.pid) {
                if i.app?.isHidden == true { i.app?.unhide(); _ = await waitUntil(timeoutMs: 500) { i.app?.isHidden == false } }
                _ = axSetFrame(w, f)
            }
        }
        for i in [a, b] where origHidden[i.pid] == true { i.app?.hide() }
        log.write(["spike": "S3", "event": "restored"])
    }
}
