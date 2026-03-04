// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Kuri",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "KuriCore", targets: ["KuriCore"]),
        .library(name: "KuriStore", targets: ["KuriStore"]),
        .library(name: "KuriSync", targets: ["KuriSync"]),
        .library(name: "KuriObservability", targets: ["KuriObservability"])
    ],
    targets: [
        .target(
            name: "KuriCore"
        ),
        .target(
            name: "KuriStore",
            dependencies: ["KuriCore"]
        ),
        .target(
            name: "KuriObservability",
            dependencies: ["KuriCore"]
        ),
        .target(
            name: "KuriSync",
            dependencies: ["KuriCore", "KuriStore", "KuriObservability"]
        ),
        .testTarget(
            name: "KuriCoreTests",
            dependencies: ["KuriCore"]
        ),
        .testTarget(
            name: "KuriStoreTests",
            dependencies: ["KuriStore"]
        ),
        .testTarget(
            name: "KuriSyncTests",
            dependencies: ["KuriSync", "KuriStore"]
        ),
        .testTarget(
            name: "KuriObservabilityTests",
            dependencies: ["KuriObservability"]
        )
    ]
)
