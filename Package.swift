// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Ava",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(name: "Ava", dependencies: ["KeyboardShortcuts"]),
        .testTarget(name: "AvaTests", dependencies: ["Ava"]),
    ]
)
