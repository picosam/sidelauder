// S1 (activation ladder, spec §9.7) and S2 (hide and unhide from a
// non-active process, §9.8), plus the hotkey inventory for S13/D-11.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// The driver's side of the subject (Subject.swift): launch it, learn where
/// its panel is, send it commands and collect its answers.
@MainActor
final class SubjectLink {
    var pid: pid_t = 0
    var panelWindow = 0
    var panelPoint = CGPoint.zero
    var axTrusted: Bool?
    var acks: [(kind: String, info: [AnyHashable: Any], t: Double)] = []
    var tokens: [NSObjectProtocol] = []
    var app: NSRunningApplication?

    func start(_ insts: [Instance], out: String) async -> Bool {
        let dnc = DistributedNotificationCenter.default()
        tokens.append(dnc.addObserver(forName: helloName, object: nil, queue: .main) { [weak self] n in
            let t = nowMs()
            MainActor.assumeIsolated {
                guard let self, let u = n.userInfo else { return }
                self.pid = (u["pid"] as? NSNumber)?.int32Value ?? 0
                self.panelWindow = (u["windowNumber"] as? NSNumber)?.intValue ?? 0
                self.panelPoint = CGPoint(x: (u["x"] as? NSNumber)?.doubleValue ?? 0, y: (u["y"] as? NSNumber)?.doubleValue ?? 0)
                self.axTrusted = (u["axTrusted"] as? NSNumber)?.boolValue
                _ = t
            }
        })
        tokens.append(dnc.addObserver(forName: ackName, object: nil, queue: .main) { [weak self] n in
            let t = nowMs()
            MainActor.assumeIsolated { self?.acks.append((n.userInfo?["kind"] as? String ?? "", n.userInfo ?? [:], t)) }
        })
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SpikeSubject.app")
        let cfg = NSWorkspace.OpenConfiguration()
        var args = ["subject", "--out", out + ".subject"]
        for i in insts { args += ["--\(i.label.lowercased())", String(i.pid)] }
        cfg.arguments = args
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        app = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        return await waitUntil(timeoutMs: 5000) { self.pid != 0 } != nil
    }

    func send(_ action: String, _ info: [String: Any] = [:]) {
        var u = info
        u["action"] = action
        postDistributed(cmdName, u)
    }

    func ack(_ kind: String, after t: Double, timeoutMs: Double) async -> [AnyHashable: Any]? {
        var hit: [AnyHashable: Any]?
        _ = await waitUntil(timeoutMs: timeoutMs) {
            hit = self.acks.first { $0.kind == kind && $0.t >= t }?.info
            return hit != nil
        }
        return hit
    }

    func stop() {
        send("quit")
        for t in tokens { DistributedNotificationCenter.default().removeObserver(t) }
    }
}

@MainActor
final class ActivationSpikes {
    let log: ResultLog
    let watch: WorkspaceWatch
    let panel: RailPanel
    let insts: [Instance]
    let me = getpid()
    /// A second SpikeRunner showing a text window: the front app with recent
    /// typing, for the typed-* conditions. Synthetic letters go only to it.
    var typist: NSRunningApplication?
    /// When set, the un-granted subject makes the activation calls (Mode A).
    var subject: SubjectLink?

    init(log: ResultLog, watch: WorkspaceWatch, panel: RailPanel, insts: [Instance]) {
        self.log = log; self.watch = watch; self.panel = panel; self.insts = insts
    }

    func other(_ i: Instance) -> Instance { insts.first { $0.pid != i.pid }! }

    /// Step 1: yield to the target, then ask it to activate (E26).
    func step1(_ target: NSRunningApplication) -> Bool {
        NSApp.yieldActivation(to: target)
        return target.activate(from: NSRunningApplication.current, options: [])
    }

    /// Step 3: AX frontmost, then raise the main window.
    func step3(_ pid: pid_t) -> [String] {
        let app = axApp(pid)
        let e1 = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var e2 = AXError.noValue
        if let w = axMainWindow(pid) { e2 = AXUIElementPerformAction(w, kAXRaiseAction as CFString) }
        return [e1 == .success ? "ok" : "err\(e1.rawValue)", e2 == .success ? "ok" : "err\(e2.rawValue)"]
    }

    /// Brings an instance forward for a trial's precondition, by the most
    /// reliable route available; not itself measured.
    func makeFront(_ i: Instance) async -> Bool {
        if frontmostPid() == i.pid && !NSApp.isActive { return true }
        if axTrusted() { _ = step3(i.pid) }
        return await waitUntil(timeoutMs: 2000) { frontmostPid() == i.pid && !NSApp.isActive } != nil
    }

    // MARK: S1

    /// One trial of one condition against `target`; the other instance is in front.
    func trial(_ condition: String, _ n: Int, _ target: Instance) async {
        guard let app = target.app else { log.write(["spike": "S1", "condition": condition, "trial": n, "error": "target gone"]); return }
        // typed-X: the typist is in front and has just been typed into; then X.
        let typed = condition.hasPrefix("typed-")
        let base = typed ? String(condition.dropFirst("typed-".count)) : condition
        var rec: [String: Any] = ["spike": "S1", "condition": condition, "trial": n, "target": target.label]
        var pre: Bool
        let sourcePid: pid_t
        if typed {
            guard let t = typist else { rec["error"] = "no typist"; log.write(rec); return }
            sourcePid = t.processIdentifier
            _ = step3(sourcePid)
            pre = await waitUntil(timeoutMs: 1500) { frontmostPid() == sourcePid && !NSApp.isActive } != nil
        } else {
            sourcePid = other(target).pid
            pre = await makeFront(other(target))
        }
        await sleepMs(250) // let the previous switch settle
        pre = pre && frontmostPid() == sourcePid && !NSApp.isActive
        if typed && pre {
            Poster.type("asdf jkl")
            pre = frontmostPid() == sourcePid && !NSApp.isActive
        }
        rec["preconditionOk"] = pre
        if typed && !pre { rec["error"] = "typist not in front; nothing typed or triggered"; log.write(rec); return }
        var allowed: Any = NSNull()
        var step0: [String: Any] = [:]
        let t0 = nowMs()

        if let sub = subject, base != "step3" {
            rec["actor"] = "subject"
            switch base {
            case "click":
                sub.send("target", ["pid": NSNumber(value: target.pid)])
                _ = await sub.ack("target", after: t0, timeoutMs: 300)
                guard topWindowNumber(at: sub.panelPoint) == sub.panelWindow else {
                    rec["error"] = "subject panel not topmost; click not posted"; log.write(rec); return
                }
                Poster.clickAt(sub.panelPoint)
                let a = await sub.ack("click", after: t0, timeoutMs: 400)
                allowed = a?["allowed"] ?? NSNull()
            case "hotkey":
                Poster.hotkey(keyCode: target.label == "A" ? kVK_ANSI_1 : kVK_ANSI_2)
                let a = await sub.ack("hotkey", after: t0, timeoutMs: 500)
                allowed = a?["allowed"] ?? NSNull()
                step0 = ["step0Ok": a?["step0Ok"] ?? NSNull(), "step0Ms": a?["step0Ms"] ?? NSNull()]
            case "step1-inactive":
                sub.send("step1", ["pid": NSNumber(value: target.pid)])
                allowed = await sub.ack("step1", after: t0, timeoutMs: 300)?["allowed"] ?? NSNull()
            case "activate-inactive":
                sub.send("activate", ["pid": NSNumber(value: target.pid)])
                allowed = await sub.ack("activate", after: t0, timeoutMs: 300)?["allowed"] ?? NSNull()
            case "step2":
                guard let l = target.launcher else { rec["error"] = "no launcher"; log.write(rec); return }
                // Never open a launcher with a modifier held: an AppleScript
                // applet opened with Control down stops at its startup screen.
                rec["waitedForReleaseMs"] = round1(await waitUntil(timeoutMs: 2000) { modifiersReleased() })
                guard modifiersReleased() else { rec["error"] = "modifiers held; launcher not opened"; log.write(rec); return }
                sub.send("step2", ["launcher": l.path])
            default:
                rec["error"] = "unknown condition"
            }
        } else {
        rec["actor"] = "runner"
        switch base {
        case "click":
            // The rail click: the panel's mouseDown runs step 1.
            var handled: Double?
            panel.view.onMouseDown = { [weak self] t in
                handled = t
                allowed = self?.step1(app) ?? false
            }
            guard Poster.click(panel) else { rec["error"] = "panel not topmost; click not posted"; log.write(rec); return }
            _ = await waitUntil(timeoutMs: 300) { handled != nil }
            rec["clickHandledMs"] = round1(handled.map { $0 - t0 })
        case "hotkey":
            // Step 0 on the strength of the hotkey, then step 1 (§9.7).
            var fired: Double?
            hotKeyHandler = { _ in
                fired = nowMs()
                NSApp.activate()
            }
            Poster.hotkey(keyCode: target.label == "A" ? kVK_ANSI_1 : kVK_ANSI_2)
            _ = await waitUntil(timeoutMs: 300) { fired != nil }
            _ = await waitUntil(timeoutMs: 100) { NSApp.isActive }
            let own = watch.first("activate", pid: me, after: t0)
            step0 = ["hotkeyFiredMs": round1(fired.map { $0 - t0 }), "step0Ok": NSApp.isActive,
                     "step0Ms": round1(own.map { $0.t - t0 })]
            allowed = step1(app)
        case "step1-inactive":
            // The control: step 1 with no user input behind it.
            allowed = step1(app)
        case "activate-inactive":
            // Baseline: a plain activate from an inactive app, no yield.
            allowed = app.activate(options: [])
        case "step2":
            guard let l = target.launcher else { rec["error"] = "no launcher"; log.write(rec); return }
            rec["waitedForReleaseMs"] = round1(await waitUntil(timeoutMs: 2000) { modifiersReleased() })
            guard modifiersReleased() else { rec["error"] = "modifiers held; launcher not opened"; log.write(rec); return }
            do {
                let cfg = NSWorkspace.OpenConfiguration()
                _ = try await NSWorkspace.shared.openApplication(at: l, configuration: cfg)
            } catch { rec["error"] = "\(error)" }
        case "step3":
            rec["axErrors"] = step3(target.pid)
        default:
            rec["error"] = "unknown condition"
        }
        }

        // Time to the activation notification and to the target's window
        // being the front one, both from t0, in one polling loop.
        let budget: Double = base == "step2" ? 1500 : 300
        var frontAt: Double?
        _ = await waitUntil(timeoutMs: budget + 400) {
            if frontAt == nil && frontWindowOwner() == target.pid { frontAt = nowMs() }
            return frontAt != nil && self.watch.first("activate", pid: target.pid, after: t0) != nil
        }
        let actMs = watch.first("activate", pid: target.pid, after: t0).map { $0.t - t0 }
        let frontMs = frontAt.map { $0 - t0 }
        if base == "step2" {
            // Everything that activated, hid or launched meanwhile, labelled
            // without names: A, B, subject, self, or the app's bundle kind.
            await sleepMs(1500)
            rec["events"] = watch.all(after: t0).map { e -> String in
                let who = insts.first { $0.pid == e.pid }?.label ?? (e.pid == me ? "self" : e.pid == subject?.pid ? "subject" :
                    (NSRunningApplication(processIdentifier: e.pid)?.bundleIdentifier?.hasPrefix("com.claude-multiprofile.") == true ? "launcher" :
                     NSRunningApplication(processIdentifier: e.pid)?.bundleIdentifier ?? "gone"))
                return "\(e.kind):\(who)@\(Int(e.t - t0))"
            }
        }
        rec.merge(step0) { a, _ in a }
        rec["allowed"] = allowed
        rec["activateMs"] = round1(actMs)
        rec["frontMs"] = round1(frontMs)
        rec["ok"] = (actMs.map { $0 <= budget } ?? false) && (frontMs.map { $0 <= budget } ?? false)
        rec["selfActivated"] = watch.first("activate", pid: subject?.pid ?? me, after: t0) != nil
        log.write(rec)
        panel.view.onMouseDown = nil
        hotKeyHandler = nil
    }

    func s1(conditions: [String], trials: Int, useSubject: Bool, out: String) async {
        var hk: [String: Any] = [:]
        if useSubject {
            let sub = SubjectLink()
            guard await sub.start(insts, out: out) else { log.write(["spike": "S1", "error": "subject did not start"]); return }
            subject = sub
            log.write(["spike": "S1", "event": "subject", "subjectAxTrusted": sub.axTrusted.map { $0 as Any } ?? NSNull()])
            hk = ["ctrlOpt1": 0, "ctrlOpt2": 0] // registered by the subject; see its log
        } else if conditions.contains(where: { $0.hasSuffix("hotkey") }) {
            hk["ctrlOpt1"] = Int(HotKeys.register(id: 1, keyCode: kVK_ANSI_1, modifiers: ctrlOpt))
            hk["ctrlOpt2"] = Int(HotKeys.register(id: 2, keyCode: kVK_ANSI_2, modifiers: ctrlOpt))
        }
        log.write(["spike": "S1", "event": "start", "conditions": conditions, "trials": trials,
                   "axTrusted": axTrusted(), "postEventAccess": CGPreflightPostEventAccess(), "hotkeys": hk])
        if !useSubject { panel.orderFrontRegardless() }
        if conditions.contains(where: { $0.hasPrefix("typed-") }), let out = CommandLine.arguments.firstIndex(of: "--out")
            .map({ CommandLine.arguments[$0 + 1] }) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.arguments = ["typist", "--out", out + ".typist"]
            cfg.createsNewApplicationInstance = true
            cfg.activates = false
            typist = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg)
            await sleepMs(1500)
            log.write(["spike": "S1", "event": "typist", "launched": typist != nil])
        }
        for c in conditions {
            if c.hasSuffix("hotkey") && (hk["ctrlOpt1"] as? Int != 0 || hk["ctrlOpt2"] as? Int != 0) {
                log.write(["spike": "S1", "condition": c, "error": "hotkey registration failed; not posting keys"])
                continue
            }
            if c == "step3" && !axTrusted() { log.write(["spike": "S1", "condition": c, "error": "no Accessibility grant"]); continue }
            if (c.hasSuffix("click") || c.hasSuffix("hotkey") || c.hasPrefix("typed-")) && !CGPreflightPostEventAccess() {
                log.write(["spike": "S1", "condition": c, "error": "cannot post events (Accessibility)"]); continue
            }
            for n in 1...trials {
                await trial(c, n, insts[n % 2])
            }
        }
        HotKeys.unregisterAll()
        typist?.terminate()
        subject?.stop()
        log.write(["spike": "S1", "event": "end"])
    }

    // MARK: S1 with real hands

    /// The operator types in one profile and presses the real hotkey for the
    /// other (⌃⌥1 = A, ⌃⌥2 = B), or clicks the subject's square. Each hotkey or
    /// click the subject reports is one trial; SpikeRunner posts nothing.
    func s1Real(count: Int, out: String) async {
        let sub = SubjectLink()
        guard await sub.start(insts, out: out) else { log.write(["spike": "S1", "error": "subject did not start"]); return }
        subject = sub
        log.write(["spike": "S1", "event": "real-start", "count": count])
        var seen = 0
        var since = nowMs()
        while seen < count {
            // Keep the square's target on the profile that is not in front.
            if let front = insts.first(where: { $0.pid == frontmostPid() }) {
                sub.send("target", ["pid": NSNumber(value: other(front).pid)])
            }
            guard let a = sub.acks.first(where: { ($0.kind == "hotkey" || $0.kind == "click") && $0.t > since }) else {
                await sleepMs(20)
                if nowMs() - since > 15 * 60 * 1000 { break }
                continue
            }
            since = a.t
            seen += 1
            let label = a.info["target"] as? String ?? "?"
            guard let target = insts.first(where: { $0.label == label }) else { continue }
            let t0 = (a.info["fired"] as? NSNumber)?.doubleValue ?? (a.info["handled"] as? NSNumber)?.doubleValue ?? a.t
            var frontAt: Double?
            _ = await waitUntil(timeoutMs: 700) {
                if frontAt == nil && frontWindowOwner() == target.pid { frontAt = nowMs() }
                return frontAt != nil && self.watch.first("activate", pid: target.pid, after: t0) != nil
            }
            let actMs = watch.first("activate", pid: target.pid, after: t0).map { $0.t - t0 }
            log.write(["spike": "S1", "condition": "real-\(a.kind)", "actor": "subject", "trial": seen, "target": label,
                       "preconditionOk": true, "allowed": a.info["allowed"] ?? NSNull(),
                       "step0Ok": a.info["step0Ok"] ?? NSNull(),
                       "activateMs": round1(actMs), "frontMs": round1(frontAt.map { $0 - t0 }),
                       "ok": (actMs.map { $0 <= 300 } ?? false) && (frontAt.map { $0 - t0 <= 300 } ?? false)])
            NSSound(named: "Tink")?.play()
        }
        sub.stop()
        log.write(["spike": "S1", "event": "end"])
    }

    // MARK: S2

    /// Hide then unhide the background instance while another is active and
    /// SpikeRunner is not (the moment Solo hides, spec §9.2).
    func s2(trials: Int, useSubject: Bool, out: String) async {
        if useSubject {
            let sub = SubjectLink()
            guard await sub.start(insts, out: out) else { log.write(["spike": "S2", "error": "subject did not start"]); return }
            subject = sub
        }
        log.write(["spike": "S2", "event": "start", "trials": trials, "actor": useSubject ? "subject" : "runner"])
        for n in 1...trials {
            let front = insts[n % 2], back = other(front)
            guard let app = back.app else { continue }
            _ = await makeFront(front)
            if app.isHidden { app.unhide(); _ = await waitUntil(timeoutMs: 1000) { !app.isHidden } }
            await sleepMs(200)
            var rec: [String: Any] = ["spike": "S2", "trial": n, "target": back.label,
                                      "preconditionOk": frontmostPid() == front.pid && !NSApp.isActive && !app.isHidden]
            var t0 = nowMs()
            if let sub = subject {
                sub.send("hide", ["pid": NSNumber(value: back.pid)])
                rec["hideReturned"] = await sub.ack("hide", after: t0, timeoutMs: 300)?["allowed"] ?? NSNull()
            } else {
                rec["hideReturned"] = app.hide()
            }
            let hid = await waitUntil(timeoutMs: 1000) { self.watch.first("hide", pid: back.pid, after: t0) != nil && app.isHidden }
            rec["hideMs"] = round1(hid)
            rec["frontAfterHide"] = frontmostPid() == front.pid ? "unchanged" : "changed"
            await sleepMs(200)
            t0 = nowMs()
            if let sub = subject {
                sub.send("unhide", ["pid": NSNumber(value: back.pid)])
                rec["unhideReturned"] = await sub.ack("unhide", after: t0, timeoutMs: 300)?["allowed"] ?? NSNull()
            } else {
                rec["unhideReturned"] = app.unhide()
            }
            let shown = await waitUntil(timeoutMs: 1000) { self.watch.first("unhide", pid: back.pid, after: t0) != nil && !app.isHidden }
            rec["unhideMs"] = round1(shown)
            rec["frontAfterUnhide"] = frontmostPid() == front.pid ? "unchanged" : "changed"
            rec["ok"] = hid != nil && shown != nil
            log.write(rec)
        }
        subject?.stop()
        log.write(["spike": "S2", "event": "end"])
    }

    // MARK: Hotkey inventory (S13, for D-11)

    func hotkeyInventory() {
        var out: [String: Int] = [:]
        var id: UInt32 = 100
        let combos: [(String, Int, Int)] =
            (0...9).map { ("ctrl-opt-\($0)", digitKeys[$0], ctrlOpt) } +
            [("ctrl-opt-]", kVK_ANSI_RightBracket, ctrlOpt), ("ctrl-opt-[", kVK_ANSI_LeftBracket, ctrlOpt),
             ("ctrl-opt-tab", kVK_Tab, ctrlOpt)] +
            (1...3).map { ("ctrl-opt-shift-\($0)", digitKeys[$0], ctrlOptShift) }
        for (name, key, mods) in combos {
            out[name] = Int(HotKeys.register(id: id, keyCode: key, modifiers: mods))
            id += 1
        }
        HotKeys.unregisterAll()
        log.write(["spike": "S13", "event": "registration", "status": out])
    }
}
