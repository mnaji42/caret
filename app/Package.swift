// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caret",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique pure, sans dépendance système, donc testable.
        .target(
            name: "CaretCore",
            path: "Sources/CaretCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Caret",
            dependencies: ["CaretCore"],
            path: "Sources/Caret",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CaretCoreTests",
            dependencies: ["CaretCore"],
            path: "Tests/CaretCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
