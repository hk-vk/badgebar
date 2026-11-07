// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BadgeBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "BadgeBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/BadgeBar"
        ),
        .testTarget(
            name: "BadgeBarTests",
            dependencies: ["BadgeBar"],
            path: "Tests/BadgeBarTests"
        ),
    ]
)
