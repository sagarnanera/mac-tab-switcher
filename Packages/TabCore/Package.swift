// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TabCore", targets: ["TabCore"])
    ],
    targets: [
        .target(
            name: "TabCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TabCoreTests",
            dependencies: ["TabCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
