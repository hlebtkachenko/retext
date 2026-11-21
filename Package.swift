// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Retext",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "RetextCore"),
        .executableTarget(name: "Retext", dependencies: ["RetextCore"]),
        .testTarget(name: "RetextCoreTests", dependencies: ["RetextCore"]),
        .testTarget(name: "RetextTests", dependencies: ["Retext"]),
    ]
)
