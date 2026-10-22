// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorkoutStore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WorkoutStore", targets: ["WorkoutStore"])],
    dependencies: [
        .package(path: "../WorkoutEngine"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "WorkoutStore",
            dependencies: ["WorkoutEngine", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "WorkoutStoreTests", dependencies: ["WorkoutStore"]),
    ]
)
