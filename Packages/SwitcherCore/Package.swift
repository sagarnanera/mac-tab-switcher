// swift-tools-version: 6.0
import PackageDescription

/// Pure decision logic. Imports Foundation, CoreGraphics and CryptoKit only.
///
/// Kept as its own package so the whole test suite runs in CI with no GUI session,
/// no Accessibility grant and no Xcode — and so that "is this logic or is this
/// plumbing?" has a structural answer rather than a stylistic one.
let package = Package(
    name: "SwitcherCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwitcherCore", targets: ["SwitcherCore"])],
    targets: [
        .target(
            name: "SwitcherCore",
            // Kernels keep their behaviour spec beside the code. SwiftPM would
            // otherwise treat them as undeclared resources. Add each new one here.
            exclude: [
                "Kernels/OverlayStateMachineSpecs.md",
                "Kernels/DwellPolicySpecs.md",
                "Kernels/AppGroupingSpecs.md",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwitcherCoreTests",
            dependencies: ["SwitcherCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
