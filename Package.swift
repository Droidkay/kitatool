// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchPlayer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchPlayer",
            path: "Sources/NotchPlayer"
        )
    ]
)
