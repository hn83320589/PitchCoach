// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PitchCoachKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MusicTheory", targets: ["MusicTheory"]),
        .library(name: "PitchDetection", targets: ["PitchDetection"]),
        .library(name: "PracticeEngine", targets: ["PracticeEngine"]),
        .library(name: "SignalKit", targets: ["SignalKit"]),
        .library(name: "Accompaniment", targets: ["Accompaniment"]),
    ],
    targets: [
        .target(name: "MusicTheory"),
        .target(name: "PitchDetection"),
        .target(name: "PracticeEngine", dependencies: ["MusicTheory", "PitchDetection"]),
        .target(name: "SignalKit"),
        .target(name: "Accompaniment"),
        .testTarget(name: "MusicTheoryTests", dependencies: ["MusicTheory"]),
        .testTarget(name: "SignalKitTests", dependencies: ["SignalKit"]),
        .testTarget(name: "PitchDetectionTests", dependencies: ["PitchDetection", "SignalKit"]),
        .testTarget(name: "AccompanimentTests", dependencies: ["Accompaniment", "PitchDetection"]),
        .testTarget(name: "PracticeEngineTests", dependencies: ["PracticeEngine", "MusicTheory", "PitchDetection"]),
    ]
)
