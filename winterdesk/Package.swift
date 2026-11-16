// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WinterDesk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WinterDesk", path: "Sources/WinterDesk")
    ]
)
