// Shared plumbing for the M0 spikes: arguments, the result log, time, the
// front window, process trees and the instances under test.
//
// Every record names instances by label (A, B), never by profile name or
// path, so result files can be summarised in the public repository.

import AppKit
import ApplicationServices
import Darwin
import Foundation

// MARK: Arguments

struct Args {
    let all: [String]
    init() { all = Array(CommandLine.arguments.dropFirst()) }
    var mode: String { all.first ?? "help" }
    func value(_ name: String) -> String? {
        guard let i = all.firstIndex(of: name), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
    func int(_ name: String, _ fallback: Int) -> Int { value(name).flatMap(Int.init) ?? fallback }
    func has(_ name: String) -> Bool { all.contains(name) }
}

// MARK: Time

/// Milliseconds on the monotonic clock.
func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

func sleepMs(_ ms: Double) async { try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000)) }

/// Polls `condition` every `stepMs` until it holds or `timeoutMs` passes.
/// Returns the elapsed milliseconds when it held, nil on timeout.
@MainActor
func waitUntil(timeoutMs: Double, stepMs: Double = 2, _ condition: () -> Bool) async -> Double? {
    let start = nowMs()
    while nowMs() - start < timeoutMs {
        if condition() { return nowMs() - start }
        await sleepMs(stepMs)
    }
    return condition() ? nowMs() - start : nil
}

// MARK: Result log (JSON lines)

final class ResultLog {
    let handle: FileHandle
    init(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)!
    }
    func write(_ record: [String: Any]) {
        var r = record
        r["t"] = (nowMs() * 10).rounded() / 10
        let data = try! JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}

func round1(_ x: Double?) -> Any { x.map { ($0 * 10).rounded() / 10 } ?? NSNull() }

// MARK: Instances under test

/// A Claude instance the spike acts on, known by label only.
struct Instance {
    let label: String
    let pid: pid_t
    let launcher: URL?
    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
}

/// Parses `--a <pid> [--launcher-a <path>] --b <pid> [--launcher-b <path>]`.
func instances(_ args: Args) -> [Instance] {
    var out: [Instance] = []
    for label in ["a", "b", "c"] {
        guard let pid = args.value("--\(label)").flatMap(Int32.init) else { continue }
        let launcher = args.value("--launcher-\(label)").map { URL(fileURLWithPath: $0) }
        out.append(Instance(label: label.uppercased(), pid: pid, launcher: launcher))
    }
    return out
}

// MARK: Activation observation

/// Records every app activation, hide and unhide with its time, so a trial
/// can ask "did pid P activate after time T?".
@MainActor
final class WorkspaceWatch {
    struct Event { let kind: String; let pid: pid_t; let t: Double }
    private(set) var events: [Event] = []
    private var tokens: [NSObjectProtocol] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        let kinds: [(NSNotification.Name, String)] = [
            (NSWorkspace.didActivateApplicationNotification, "activate"),
            (NSWorkspace.didHideApplicationNotification, "hide"),
            (NSWorkspace.didUnhideApplicationNotification, "unhide"),
            (NSWorkspace.didLaunchApplicationNotification, "launch"),
            (NSWorkspace.didTerminateApplicationNotification, "terminate"),
        ]
        for (name, kind) in kinds {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let t = nowMs()
                MainActor.assumeIsolated { self?.events.append(Event(kind: kind, pid: app.processIdentifier, t: t)) }
            })
        }
    }

    func first(_ kind: String, pid: pid_t, after t: Double) -> Event? {
        events.first { $0.kind == kind && $0.pid == pid && $0.t >= t }
    }
    func all(after t: Double) -> [Event] { events.filter { $0.t >= t } }
}

// MARK: The front window (no permission needed, spec 4.2.7)

/// The owner PID of the frontmost normal-layer on-screen window.
func frontWindowOwner() -> pid_t? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return nil }
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0,
              let b = w[kCGWindowBounds as String] as? [String: Double], (b["Width"] ?? 0) > 50, (b["Height"] ?? 0) > 50
        else { continue }
        return w[kCGWindowOwnerPID as String] as? pid_t
    }
    return nil
}

/// The number of the topmost on-screen window at a global (top-left) point,
/// skipping the full-screen overlays that clicks pass through.
func topWindowNumber(at p: CGPoint) -> Int? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return nil }
    for w in list {
        guard let b = w[kCGWindowBounds as String] as? [String: Double],
              let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
        // Click-through overlays that cover the whole screen: the Dock's, and
        // the Screenshot tool's while a screen recording runs.
        // The window server's own windows (the cursor image) take no clicks either.
        if ["Dock", "Screenshot", "screencaptureui", "Window Server"].contains(w[kCGWindowOwnerName as String] as? String ?? "") { continue }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if r.contains(p) { return w[kCGWindowNumber as String] as? Int }
    }
    return nil
}

/// Every on-screen window containing a point, front to back (diagnostics).
func windowsAt(_ p: CGPoint) -> [[String: Any]] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return [] }
    return list.compactMap { w in
        guard let b = w[kCGWindowBounds as String] as? [String: Double] else { return nil }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard r.contains(p) else { return nil }
        let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
        return ["owner": pid == getpid() ? "self" : (w[kCGWindowOwnerName as String] as? String ?? "?"),
                "layer": w[kCGWindowLayer as String] as? Int ?? -1, "alpha": w[kCGWindowAlpha as String] as? Double ?? -1,
                "w": r.width, "h": r.height]
    }
}

func frontmostPid() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

// MARK: Process trees and CPU (S14)

/// The pid and every descendant.
func processTree(_ root: pid_t) -> [pid_t] {
    var out: [pid_t] = [root]
    var i = 0
    while i < out.count {
        let pid = out[i]
        let n = proc_listchildpids(pid, nil, 0)
        if n > 0 {
            var buf = [pid_t](repeating: 0, count: Int(n) * 2)
            let got = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
            if got > 0 { out.append(contentsOf: buf.prefix(Int(got)).filter { $0 > 0 }) }
        }
        i += 1
    }
    return out
}

private let timebase: (numer: UInt32, denom: UInt32) = {
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    return (tb.numer, tb.denom)
}()

/// Total user + system CPU time of one process, in milliseconds.
func cpuMs(_ pid: pid_t) -> Double? {
    var info = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard r == 0 else { return nil }
    let ticks = Double(info.ri_user_time + info.ri_system_time)
    return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
}

/// Process start time (spec §8.4's liveness check reads the same field).
func startTime(_ pid: pid_t) -> timeval? {
    var kp = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
    return kp.kp_proc.p_starttime
}

// MARK: Accessibility

func axTrusted() -> Bool { AXIsProcessTrusted() }

func axApp(_ pid: pid_t) -> AXUIElement {
    let e = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(e, 0.25)
    return e
}

func axCopy(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
}

/// The main standard window, else the first standard window (spec §9.10).
func axMainWindow(_ pid: pid_t) -> AXUIElement? {
    let app = axApp(pid)
    func isStandard(_ w: AXUIElement) -> Bool { (axCopy(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole }
    if let m = axCopy(app, kAXMainWindowAttribute), CFGetTypeID(m) == AXUIElementGetTypeID() {
        let w = m as! AXUIElement
        if isStandard(w) { return w }
    }
    if let ws = axCopy(app, kAXWindowsAttribute) as? [AXUIElement] { return ws.first(where: isStandard) }
    return nil
}

func axFrame(_ w: AXUIElement) -> CGRect? {
    guard let p = axCopy(w, kAXPositionAttribute), let s = axCopy(w, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

@discardableResult
func axSetSize(_ w: AXUIElement, _ s: CGSize) -> AXError {
    var v = s
    return AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &v)!)
}

@discardableResult
func axSetPosition(_ w: AXUIElement, _ p: CGPoint) -> AXError {
    var v = p
    return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &v)!)
}

/// Size, position, size (spec Appendix A.3, after Rectangle).
func axSetFrame(_ w: AXUIElement, _ r: CGRect) -> [String] {
    let e = [axSetSize(w, r.size), axSetPosition(w, r.origin), axSetSize(w, r.size)]
    return e.map { $0 == .success ? "ok" : "err\($0.rawValue)" }
}

extension CGRect {
    func within(_ o: CGRect, _ tol: CGFloat) -> Bool {
        abs(minX - o.minX) <= tol && abs(minY - o.minY) <= tol && abs(width - o.width) <= tol && abs(height - o.height) <= tol
    }
    var dict: [String: Double] { ["x": minX, "y": minY, "w": width, "h": height] }
}

// MARK: Summaries

func percentile(_ xs: [Double], _ p: Double) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}
