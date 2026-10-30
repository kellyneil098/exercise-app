// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorkoutUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WorkoutUI", targets: ["WorkoutUI"])],
    dependencies: [.package(path: "../WorkoutEngine")],
    targets: [
        .target(name: "WorkoutUI", dependencies: ["WorkoutEngine"],
                swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(name: "WorkoutUITests", dependencies: ["WorkoutUI", "WorkoutEngine"]),
    ]
)
