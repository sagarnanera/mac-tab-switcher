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
            // Each kernel keeps its behaviour spec in the same directory as the code
            // it describes, which SwiftPM would otherwise treat as an undeclared
            // resource. Add every new *Specs.md here.
            exclude: ["Kernels/AppGroupingSpecs.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TabCoreTests",
            dependencies: ["TabCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
