// SpikeRunner: the M0 harness for S1, S2, S3, S14 and S15 (spec §16.1), and
// the hotkey inventory behind D-11.
//
// Start it through LaunchServices so TCC treats it as its own app (a binary
// run from a terminal is judged by the terminal's grants):
//
//   open -W -n SpikeRunner.app --args <mode> --out <results.jsonl> [options]
//
// Modes and options:
//   status [--prompt]                          grants, liveness of --a/--b
//   hotkeys                                    try to register the §6.5 defaults
//   s1 --a P --b P [--launcher-a L --launcher-b L] --trials N --conditions c1,c2,...
//        conditions: click, hotkey, step1-inactive, activate-inactive, step2, step3, and each
//        of these as typed-<condition>: first a SpikeRunner typist window is put in front
//        and typed into, so the switch starts from an app with recent input
//        --subject: an un-granted copy (SpikeSubject.app) makes the activation calls, as
//        Mode A will; SpikeRunner only sets up, posts the input and measures
//   s1-real --a P --b P --count N               the operator's real hotkeys and clicks
//   s2 --a P --b P --trials N [--subject]
//   s3 --a P --b P --variant 1|2 --switches N [--perturb]
//   s14 --a P [--b P] --condition visible|hidden|covered --kind chat|code
//       [--reveal-after S] [--max S]
//   s15 --a P --b P [--c P] --clicks N
//   restore --a P --b P                         unhide both
//   poke [--front P] --hotkey N [--shift] | --click-panel   smoke tests only: press ⌃⌥(⇧)N, or click
//        the subject's square, and only while a spike app is the one it reaches
//
// It acts only on the PIDs it is given and labels them A, B, C in its log.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class Runner: NSObject, NSApplicationDelegate {
    let args = Args()

    func applicationDidFinishLaunching(_ note: Notification) {
        Task { @MainActor in
            await run()
            NSApp.terminate(nil)
        }
    }

    func run() async {
        guard let out = args.value("--out") else {
            FileHandle.standardError.write(Data("--out <file> is required\n".utf8))
            return
        }
        let log = ResultLog(path: out)
        let watch = WorkspaceWatch()
        let panel = RailPanel()
        let insts = instances(args)
        let act = ActivationSpikes(log: log, watch: watch, panel: panel, insts: insts)
        log.write(["event": "launch", "mode": args.mode, "pid": Int(getpid()),
                   "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                   "instances": insts.map { ["label": $0.label, "alive": $0.app != nil, "hidden": $0.app?.isHidden ?? false] }])

        let needTwo = ["s1", "s1-real", "s2", "s3", "s15", "restore"]
        if needTwo.contains(args.mode) && insts.count < 2 {
            log.write(["error": "needs --a and --b"])
            return
        }
        switch args.mode {
        case "status":
            // --prompt asks macOS to show its Accessibility prompt for this app.
            if args.has("--prompt") {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            panel.orderFrontRegardless()
            await sleepMs(300)
            log.write(["panelPoint": ["x": panel.clickPoint.x, "y": panel.clickPoint.y],
                       "windowsAtPanelPoint": windowsAt(panel.clickPoint)])
            log.write(["axTrusted": axTrusted(), "postEventAccess": CGPreflightPostEventAccess(),
                       "frontOwnerIsInstance": insts.first { $0.pid == frontWindowOwner() }?.label ?? "none",
                       "startTimes": insts.map { startTime($0.pid).map { Int($0.tv_sec) } ?? -1 }])
        case "hotkeys":
            act.hotkeyInventory()
        case "s1":
            let conditions = (args.value("--conditions") ?? "step1-inactive").split(separator: ",").map(String.init)
            await act.s1(conditions: conditions, trials: args.int("--trials", 50), useSubject: args.has("--subject"), out: out)
        case "s1-real":
            await act.s1Real(count: args.int("--count", 20), out: out)
        case "s2":
            await act.s2(trials: args.int("--trials", 50), useSubject: args.has("--subject"), out: out)
        case "s3":
            let frames = FrameSpikes(log: log, watch: watch, panel: panel, act: act, insts: insts)
            frames.perturb = args.has("--perturb")
            await frames.s3(variant: args.int("--variant", 1), switches: args.int("--switches", 30))
        case "s14":
            let hidden = HiddenSpikes(log: log, watch: watch, act: act, insts: insts)
            await hidden.s14(condition: args.value("--condition") ?? "visible", kind: args.value("--kind") ?? "chat",
                             revealAfter: args.value("--reveal-after").flatMap(Double.init),
                             maxSeconds: Double(args.int("--max", 900)))
        case "s15":
            let hidden = HiddenSpikes(log: log, watch: watch, act: act, insts: insts)
            await hidden.s15(clicks: args.int("--clicks", 10))
        case "subject":
            let subject = Subject(panel: panel, insts: insts)
            await subject.run(log: log)
            withExtendedLifetime(subject) {}
        case "typist":
            // A plain window with a text view: the front app that has just
            // been typed into, for S1's typed-* conditions. Runs until quit.
            NSApp.setActivationPolicy(.regular)
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 160),
                             styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            w.title = "SpikeRunner typist"
            let tv = NSTextView(frame: w.contentView!.bounds)
            tv.autoresizingMask = [.width, .height]
            w.contentView?.addSubview(tv)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(tv)
            while true { await sleepMs(1000) }
        case "applet-probe":
            // Does a modifier held at launch stop an AppleScript applet (the
            // kind upstream's launchers are) at its startup screen? The applet
            // must be a throwaway whose script appends to --marker.
            guard let applet = args.value("--applet"), let marker = args.value("--marker") else { break }
            await appletProbe(URL(fileURLWithPath: applet), marker: marker, log: log)
        case "poke":
            log.write(await poke(args))
        case "restore":
            for i in insts where i.app?.isHidden == true { i.app?.unhide() }
            log.write(["event": "restored"])
        default:
            log.write(["error": "unknown mode \(args.mode)"])
        }
        panel.orderOut(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let runner = Runner()
    app.delegate = runner
    app.setActivationPolicy(.accessory)
    app.run()
}
