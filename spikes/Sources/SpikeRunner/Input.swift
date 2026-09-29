// The rail stand-in, global hotkeys and the synthetic events that drive them.
//
// Synthetic events go ONLY to SpikeRunner itself, never to Claude (spec I6):
// a click is posted only after CGWindowList confirms SpikeRunner's panel is
// the topmost window at that point, and a hotkey only when its registration
// succeeded, so the system hands it to SpikeRunner before any app sees it.
// Posting events needs the Accessibility grant.

import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: The panel (a stand-in for the rail: an activating panel, spec §6.1)

final class ClickView: NSView {
    var onMouseDown: ((Double) -> Void)?
    override func mouseDown(with event: NSEvent) { onMouseDown?(nowMs()) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.withAlphaComponent(0.85).setFill()
        bounds.fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class RailPanel: NSPanel {
    let view = ClickView()
    init() {
        let screen = NSScreen.screens[0].visibleFrame
        super.init(contentRect: NSRect(x: screen.minX + 8, y: screen.minY + 8, width: 48, height: 48),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        contentView = view
    }
    override var canBecomeKey: Bool { true }

    /// The panel's centre in global top-left coordinates (spec §9.9).
    var clickPoint: CGPoint {
        let primaryMaxY = NSScreen.screens[0].frame.maxY
        return CGPoint(x: frame.midX, y: primaryMaxY - frame.midY)
    }
}

// MARK: Hotkeys (Carbon RegisterEventHotKey, spec §6.5)

nonisolated(unsafe) var hotKeyHandler: ((UInt32) -> Void)?

enum HotKeys {
    static var refs: [UInt32: EventHotKeyRef] = [:]
    static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            hotKeyHandler?(id.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers one hotkey; returns the OSStatus.
    @discardableResult
    static func register(id: UInt32, keyCode: Int, modifiers: Int) -> OSStatus {
        install()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x534C_4452, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref }
        return status
    }

    static func unregisterAll() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
    }
}

let ctrlOpt = controlKey | optionKey
let ctrlOptShift = controlKey | optionKey | shiftKey
let digitKeys = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

// MARK: Synthetic events (to SpikeRunner only)

enum Poster {
    /// Clicks the panel. Refuses unless the panel is the topmost window there.
    static func click(_ panel: RailPanel) -> Bool {
        let p = panel.clickPoint
        guard topWindowNumber(at: p) == panel.windowNumber else { return false }
        let saved = CGEvent(source: nil)?.location
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        if let saved { CGWarpMouseCursorPosition(saved) }
        return true
    }

    /// Types letters into the front app. The caller checks that the front app
    /// is SpikeRunner's own typist window, never Claude (I6).
    static func type(_ text: String, gapMs: UInt32 = 25) {
        let keys: [Character: Int] = ["a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F, "j": kVK_ANSI_J,
                                      "k": kVK_ANSI_K, "l": kVK_ANSI_L, " ": kVK_Space]
        for ch in text {
            guard let k = keys[ch] else { continue }
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(k), keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(k), keyDown: false)?.post(tap: .cghidEventTap)
            usleep(gapMs * 1000)
        }
    }

    /// Clicks a point the caller has checked is the subject's own panel.
    static func clickAt(_ p: CGPoint) {
        let saved = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let saved { CGWarpMouseCursorPosition(saved) }
    }

    /// Presses a registered hotkey. The caller checks the registration.
    static func hotkey(keyCode: Int, control: Bool = true, option: Bool = true, shift: Bool = false) {
        var flags: CGEventFlags = []
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        clearModifiers()
    }

    /// A synthetic key event's flags stay in the session's modifier state
    /// until another event clears them (spikes/s1: an applet then opened
    /// "with Control held" stops at its startup screen). Post a bare
    /// flags-changed event with no flags.
    static func clearModifiers() {
        let e = CGEvent(source: nil)
        e?.type = .flagsChanged
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }
}

/// True once no Control, Option, Shift or Command is held in the session.
func modifiersReleased() -> Bool {
    CGEventSource.flagsState(.combinedSessionState).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]).isEmpty
}


// MARK: S1 step 2 hazard: modifiers held while a launcher opens

/// Opens a throwaway applet under several modifier states and records whether
/// it ran (its marker file grew) and whether it is still running afterwards
/// (stopped at its startup screen).
@MainActor
func appletProbe(_ applet: URL, marker: String, log: ResultLog) async {
    func lines() -> Int { (try? String(contentsOfFile: marker, encoding: .utf8))?.split(separator: "\n").count ?? 0 }
    let cases: [(String, [Int], CGEventFlags)] = [
        ("none", [], []),
        ("control-held", [kVK_Control], [.maskControl]),
        ("option-held", [kVK_Option], [.maskAlternate]),
        ("control-option-held", [kVK_Control, kVK_Option], [.maskControl, .maskAlternate]),
        ("after-hotkey-events", [], []),
        ("after-hotkey-then-clear", [], []),
        ("none-again", [], []),
    ]
    for (name, keys, flags) in cases {
        let before = lines()
        if name == "after-hotkey-events" {
            // The hotkey helper now clears the flags itself; post the raw pair
            // without that, to show the state the old harness left behind.
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_7), keyDown: down)
                e?.flags = [.maskControl, .maskAlternate]
                e?.post(tap: .cghidEventTap)
            }
            await sleepMs(20)
        }
        if name == "after-hotkey-then-clear" { Poster.hotkey(keyCode: kVK_ANSI_7); await sleepMs(20) }
        for k in keys {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(k), keyDown: true)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        await sleepMs(50)
        let sessionFlags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        let running = try? await NSWorkspace.shared.openApplication(at: applet, configuration: cfg)
        await sleepMs(1500)
        for k in keys.reversed() {
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(k), keyDown: false)?.post(tap: .cghidEventTap)
        }
        await sleepMs(1500)
        let stillRunning = running.map { !$0.isTerminated } ?? false
        log.write(["spike": "S1-step2", "case": name, "ran": lines() > before, "stillRunningAfter3s": stillRunning,
                   "sessionFlagsAtLaunch": Int(sessionFlags)])
        if stillRunning { running?.forceTerminate() } // a throwaway applet of ours, never a launcher
        await sleepMs(500)
    }
}
