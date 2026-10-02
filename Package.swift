// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Retext",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "RetextCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Retext", dependencies: ["RetextCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RetextCoreTests", dependencies: ["RetextCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
