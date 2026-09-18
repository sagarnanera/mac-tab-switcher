// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "tabswitcher", targets: ["TabSwitcher"])
    ],
    dependencies: [
        .package(path: "Packages/TabCore")
    ],
    targets: [
        .executableTarget(
            name: "TabSwitcher",
            dependencies: [.product(name: "TabCore", package: "TabCore")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
