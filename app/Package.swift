// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sofler",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique pure, sans dépendance système, donc testable.
        .target(
            name: "SoflerCore",
            path: "Sources/SoflerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Sofler",
            dependencies: ["SoflerCore"],
            path: "Sources/Sofler",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SoflerCoreTests",
            dependencies: ["SoflerCore"],
            path: "Tests/SoflerCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
