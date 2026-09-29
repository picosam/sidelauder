// S16 (discovery half): can an app that LaunchServices started, and so has no
// shell PATH (spec 4.1.10), find claude-multiprofile and node through the
// user's login shell, and then run the interim adapter with them?
//
// Launched as an .app from the Dock or Finder, it writes one JSON result and
// exits. `open` is NOT a stand-in for the Dock: on macOS 27 an app started by
// `open` inherits the calling shell's environment, PATH included. So the
// automated runs start it as `Discovery.app/Contents/MacOS/Discovery
// --via-workspace --out <file> --adapter <upstream-status.mjs>`, which asks
// NSWorkspace, the API the Dock and Finder use, to start a fresh instance
// with no environment of ours, and waits for its result file.
// Paths under the user's home are written as "~/..." and the result names
// only the shell's base name, so a result file can be summarised publicly.

import AppKit
import Foundation

struct Probe: Codable {
    var variant: String          // shell flags used
    var exitCode: Int32
    var timedOut: Bool
    var milliseconds: Double
    var cmp: String?              // claude-multiprofile, as found
    var node: String?
    var xdgConfigHome: String?
    var noiseBytes: Int           // stdout outside the markers (rc-file chatter)
    var stderrBytes: Int
}

struct AdapterRun: Codable {
    var exitCode: Int32
    var milliseconds: Double
    var schemaVersion: Int?
    var profiles: Int?
}

struct Result: Codable {
    var launchedPath: String?     // this process's own PATH: what LaunchServices gave it
    var shellEnv: String?         // $SHELL as inherited
    var loginShell: String        // the user record's shell (getpwuid)
    var probes: [Probe]
    var adapter: AdapterRun?
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
func tilde(_ s: String?) -> String? {
    guard let s else { return nil }
    return s.hasPrefix(home) ? "~" + s.dropFirst(home.count) : s
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func loginShell() -> String {
    if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
    return "/bin/zsh"
}

/// Runs a process with a timeout; returns (exit, stdout, stderr, ms, timedOut).
func run(_ exe: String, _ args: [String], env: [String: String]? = nil, timeout: TimeInterval = 5)
    -> (Int32, Data, Data, Double, Bool)
{
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let env { p.environment = env }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    p.standardInput = FileHandle.nullDevice
    let start = Date()
    do { try p.run() } catch { return (-1, Data(), Data(), 0, false) }
    final class Box: @unchecked Sendable { var data = Data() }
    let outBox = Box(), errBox = Box()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { outBox.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter()
    DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    var timedOut = false
    if group.wait(timeout: .now() + timeout) == .timedOut {
        // An interactive zsh ignores SIGTERM, so a polite terminate() let a
        // slow rc file run on and answer late. Kill it, give the pipes a
        // second, and let the caller discard whatever arrived.
        timedOut = true
        kill(p.processIdentifier, SIGKILL)
        _ = group.wait(timeout: .now() + 1)
    }
    p.waitUntilExit()
    return (p.terminationStatus, outBox.data, errBox.data, Date().timeIntervalSince(start) * 1000, timedOut)
}

let begin = "__SIDELAUDER_BEGIN__", sep = "__SIDELAUDER_SEP__", end = "__SIDELAUDER_END__"
let script = "printf '\\n\(begin)\\n'; command -v claude-multiprofile; printf '\(sep)\\n'; command -v node; "
    + "printf '\(sep)\\n'; printenv XDG_CONFIG_HOME; printf '\(end)\\n'"

// --zdotdir points zsh at fixture startup files, to simulate users whose
// setup differs from this Mac's (spikes/s16/zdotdir/).
func probe(_ shell: String, _ flags: [String]) -> Probe {
    var env = ProcessInfo.processInfo.environment
    if let z = arg("--zdotdir") { env["ZDOTDIR"] = z }
    let (code, out, err, ms, timedOut) = run(shell, flags + ["-c", script], env: env)
    let text = String(decoding: out, as: UTF8.self)
    var fields: [String?] = [nil, nil, nil]
    var noise = text.utf8.count
    if let b = text.range(of: begin + "\n"), let e = text.range(of: end, range: b.upperBound..<text.endIndex) {
        let body = text[b.upperBound..<e.lowerBound]
        let parts = body.components(separatedBy: sep + "\n")
        for (i, part) in parts.prefix(3).enumerated() {
            let v = part.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[i] = v.isEmpty ? nil : v
        }
        noise = text.utf8.count - text[b.lowerBound..<e.upperBound].utf8.count - 1
    }
    if timedOut { fields = [nil, nil, nil] }  // a late answer is no answer
    return Probe(variant: flags.joined(separator: " "), exitCode: code, timedOut: timedOut, milliseconds: ms,
                 cmp: tilde(fields[0]), node: tilde(fields[1]), xdgConfigHome: tilde(fields[2]),
                 noiseBytes: max(noise, 0), stderrBytes: err.count)
}

// The relaunch: hand the remaining arguments to a new instance that
// LaunchServices starts with the login session's environment, not ours.
if CommandLine.arguments.contains("--via-workspace"), let out = arg("--out") {
    let forward = CommandLine.arguments.dropFirst().filter { $0 != "--via-workspace" }
    let bundle = Bundle.main.bundleURL
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = Array(forward)
    config.createsNewApplicationInstance = true
    config.activates = false
    try? FileManager.default.removeItem(atPath: out)
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, error in
        if let error { FileHandle.standardError.write(Data("open failed: \(error)\n".utf8)) }
        done.signal()
    }
    done.wait()
    let deadline = Date().addingTimeInterval(15)
    while !FileManager.default.fileExists(atPath: out) && Date() < deadline { usleep(50_000) }
    exit(FileManager.default.fileExists(atPath: out) ? 0 : 1)
}

let env = ProcessInfo.processInfo.environment
let shell = loginShell()
var probes: [Probe] = []
for flags in [["-l"], ["-l", "-i"]] {
    probes.append(probe(shell, flags))
}

var adapterRun: AdapterRun? = nil
if let adapter = arg("--adapter"), let found = probes.first(where: { $0.cmp != nil && $0.node != nil }),
   let node = found.node.map({ $0.replacingOccurrences(of: "~", with: home, options: .anchored) }),
   let cmp = found.cmp.map({ $0.replacingOccurrences(of: "~", with: home, options: .anchored) })
{
    // Spawned as the app will spawn it (spec §8.1.2): PATH = node's directory
    // plus /usr/bin:/bin, XDG_CONFIG_HOME as found, nothing else inherited.
    var childEnv = ["PATH": (node as NSString).deletingLastPathComponent + ":/usr/bin:/bin"]
    if let x = found.xdgConfigHome { childEnv["XDG_CONFIG_HOME"] = x.replacingOccurrences(of: "~", with: home, options: .anchored) }
    let (code, out, _, ms, _) = run(node, [adapter, cmp], env: childEnv, timeout: 3)
    let json = try? JSONSerialization.jsonObject(with: out) as? [String: Any]
    adapterRun = AdapterRun(exitCode: code, milliseconds: ms, schemaVersion: json?["schemaVersion"] as? Int,
                            profiles: (json?["profiles"] as? [Any])?.count)
}

let result = Result(launchedPath: tilde(env["PATH"]), shellEnv: env["SHELL"].map { ($0 as NSString).lastPathComponent },
                    loginShell: (shell as NSString).lastPathComponent, probes: probes, adapter: adapterRun)
let outPath = arg("--out") ?? (home + "/Library/Logs/SidelauderSpikes/discovery-\(Int(Date().timeIntervalSince1970)).json")
try? FileManager.default.createDirectory(atPath: (outPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try enc.encode(result).write(to: URL(fileURLWithPath: outPath))
