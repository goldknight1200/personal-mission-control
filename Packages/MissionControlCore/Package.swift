// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MissionControlCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MissionControlCore",
            targets: ["MissionControlCore"]
        )
    ],
    targets: [
        .target(name: "MissionControlCore"),
        .testTarget(
            name: "MissionControlCoreTests",
            dependencies: ["MissionControlCore"]
        )
    ]
)
