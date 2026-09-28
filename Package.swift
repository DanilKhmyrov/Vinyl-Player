// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vinyl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vinyl", targets: ["Vinyl"]),
        .library(name: "NowPlayingBridge", type: .dynamic, targets: ["NowPlayingBridge"]),
    ],
    targets: [
        .target(
            name: "NowPlayingBridge",
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        .executableTarget(name: "Vinyl", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
