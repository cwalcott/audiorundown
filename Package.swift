// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioRundown",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "audiorundown", targets: ["AudioRundown"])],
    targets: [
        .executableTarget(name: "AudioRundown"),
        .testTarget(name: "AudioRundownTests", dependencies: ["AudioRundown"])
    ]
)
