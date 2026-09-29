// The subject: the same binary in a second bundle (SpikeSubject.app) with its
// own identity and NO Accessibility grant, standing in for Sidelauder in
// Mode A. It owns the rail panel and the hotkeys and makes every activation
// and hide call; SpikeRunner (granted) only sets up trials, posts the input
// events and measures. Without this split, SpikeRunner's own grant could be
// what lets its activations through.
//
// Commands arrive as distributed notifications, delivered immediately:
//   io.github.picosam.sidelauder.spike.cmd  {action, pid}   action: step1 | activate | hide | unhide | step2
// and the subject answers each command, click and hotkey with
//   io.github.picosam.sidelauder.spike.ack  {kind, allowed, t}

import AppKit
import Carbon.HIToolbox
import Foundation

let cmdName = Notification.Name("io.github.picosam.sidelauder.spike.cmd")
let ackName = Notification.Name("io.github.picosam.sidelauder.spike.ack")
let helloName = Notification.Name("io.github.picosam.sidelauder.spike.hello")

func postDistributed(_ name: Notification.Name, _ info: [String: Any]) {
    DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
}

@MainActor
final class Subject {
    let panel: RailPanel
    let insts: [Instance]
    var token: NSObjectProtocol?

    init(panel: RailPanel, insts: [Instance]) { self.panel = panel; self.insts = insts }

    func app(_ pid: pid_t) -> NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

    func step1(_ target: NSRunningApplication) -> Bool {
        NSApp.yieldActivation(to: target)
        return target.activate(from: NSRunningApplication.current, options: [])
    }

    /// The rail's pending target: the panel click switches to it.
    var clickTarget: pid_t = 0

    func run(log: ResultLog) async {
        panel.orderFrontRegardless()
        panel.view.onMouseDown = { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let target = self.app(self.clickTarget) else { return }
                let allowed = self.step1(target)
                postDistributed(ackName, ["kind": "click", "allowed": allowed, "handled": t,
                                          "target": self.insts.first { $0.pid == self.clickTarget }?.label ?? "?"])
            }
        }
        let hk1 = HotKeys.register(id: 1, keyCode: kVK_ANSI_1, modifiers: ctrlOpt)
        let hk2 = HotKeys.register(id: 2, keyCode: kVK_ANSI_2, modifiers: ctrlOpt)
        hotKeyHandler = { [weak self] id in
            let fired = nowMs()
            MainActor.assumeIsolated {
                let label = id == 1 ? "A" : "B"
                guard let self, let target = self.insts.first(where: { $0.label == label })?.app else { return }
                // Step 0 on the strength of the hotkey, then step 1 (spec §9.7).
                NSApp.activate()
                Task { @MainActor in
                    let own = await waitUntil(timeoutMs: 100) { NSApp.isActive }
                    let allowed = self.step1(target)
                    postDistributed(ackName, ["kind": "hotkey", "allowed": allowed, "fired": fired, "target": label,
                                              "step0Ok": own != nil, "step0Ms": own ?? -1])
                }
            }
        }
        token = DistributedNotificationCenter.default().addObserver(forName: cmdName, object: nil, queue: .main) { [weak self] note in
            let action = note.userInfo?["action"] as? String ?? ""
            let pid = (note.userInfo?["pid"] as? NSNumber)?.int32Value ?? 0
            MainActor.assumeIsolated {
                guard let self else { return }
                if action == "target" { self.clickTarget = pid; postDistributed(ackName, ["kind": "target"]); return }
                if action == "quit" { NSApp.terminate(nil); return }
                var allowed: Any = NSNull()
                if action == "step2" {
                    // Open the launcher path the driver named.
                    if let path = note.userInfo?["launcher"] as? String {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, _ in }
                    }
                } else if let a = self.app(pid) {
                    switch action {
                    case "step1": allowed = self.step1(a)
                    case "activate": allowed = a.activate(options: [])
                    case "hide": allowed = a.hide()
                    case "unhide": allowed = a.unhide()
                    default: break
                    }
                }
                postDistributed(ackName, ["kind": action, "allowed": allowed, "t": nowMs(),
                                          "subjectActive": NSApp.isActive])
            }
        }
        log.write(["event": "subject", "axTrusted": axTrusted(), "hotkeys": [Int(hk1), Int(hk2)]])
        // Tell the driver where the panel is, until it answers.
        while true {
            postDistributed(helloName, ["windowNumber": panel.windowNumber, "x": panel.clickPoint.x, "y": panel.clickPoint.y,
                                        "pid": Int(getpid()), "axTrusted": axTrusted()])
            await sleepMs(500)
        }
    }
}
