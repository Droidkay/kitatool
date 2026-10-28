// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KitaClips",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KitaClips",
            path: "Sources/KitaClips"
        )
    ]
)
