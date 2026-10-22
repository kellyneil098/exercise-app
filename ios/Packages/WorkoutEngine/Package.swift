// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorkoutEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutEngine", targets: ["WorkoutEngine"]),
    ],
    targets: [
        .target(
            name: "WorkoutEngine",
            resources: [.copy("Seed")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "WorkoutEngineTests",
            dependencies: ["WorkoutEngine"],
            resources: [.copy("Snapshots")]
        ),
    ]
)
