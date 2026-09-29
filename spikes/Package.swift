// swift-tools-version: 6.0
// M0 spikes (spec §16.1). Throwaway code: each target answers one spike's
// question with numbers and is not part of the app. Results: docs/spikes/.
import PackageDescription

let package = Package(
    name: "SidelauderSpikes",
    platforms: [.macOS("26.0")],
    targets: [
        // S16: finding claude-multiprofile and node from an app LaunchServices started.
        .executableTarget(name: "Discovery"),
        // S1, S2, S3, S14, S15: activation, hide/unhide, AX frames, hidden work, notifications.
        .executableTarget(name: "SpikeRunner"),
    ],
    // Throwaway spike code talking to Carbon and AX callbacks: Swift 5 mode
    // keeps it short. The app itself is Swift 6, strict concurrency (§7.4).
    swiftLanguageModes: [.v5]
)
