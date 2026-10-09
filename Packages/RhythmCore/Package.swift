// swift-tools-version: 6.0
import PackageDescription

/// RhythmCore holds Rhythm's deterministic, framework-independent logic: the schedule
/// engine, validation, reminder planning, import/export DTOs, the widget snapshot format,
/// Quicklink URL validation, and deep-link parsing. It depends only on Foundation so it can
/// be shared by the app and the widget extension and tested on any platform.
let package = Package(
    name: "RhythmCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RhythmCore", targets: ["RhythmCore"])
    ],
    targets: [
        .target(name: "RhythmCore"),
        .testTarget(name: "RhythmCoreTests", dependencies: ["RhythmCore"])
    ]
)
