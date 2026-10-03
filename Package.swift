// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioChapters",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "audiochapters", targets: ["AudioChapters"])],
    targets: [
        .executableTarget(name: "AudioChapters"),
        .testTarget(name: "AudioChaptersTests", dependencies: ["AudioChapters"])
    ]
)
